from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple
from datetime import datetime, timezone
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, aliased
from sqlalchemy import or_, func

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.possible_entity import PossibleEntity
from models.evidence_link import EvidenceLink
from models.case_timeline import CaseTimeline
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.report_record import ReportRecord
from models.case_status_history import CaseStatusHistory

from services.timeline_service import create_timeline_event
from services.notification_service import create_notification
from services.report_service import calculate_investigation_progress

from schemas.case_status import (
    EvidenceCountsItem,
    NextStageReadinessItem,
    CaseStatusSummaryItem,
    CaseStatusBoardResponse,
    StatusHistoryItem,
    CaseInformationItem,
    CaseStatusDetailResponse
)


# ==============================================================================
# CANONICAL STATUS MAPPINGS & TRANSITIONS
# ==============================================================================

DB_TO_CANONICAL: Dict[str, str] = {
    "Open": "OPEN",
    "In Progress": "IN_PROGRESS",
    "Under Review": "UNDER_REVIEW",
    "Closed": "CLOSED"
}

CANONICAL_TO_DB: Dict[str, str] = {
    "OPEN": "Open",
    "IN_PROGRESS": "In Progress",
    "UNDER_REVIEW": "Under Review",
    "CLOSED": "Closed"
}

ALLOWED_TRANSITIONS: Dict[str, List[str]] = {
    "OPEN": ["IN_PROGRESS"],
    "IN_PROGRESS": ["UNDER_REVIEW"],
    "UNDER_REVIEW": ["IN_PROGRESS", "CLOSED"],
    "CLOSED": []
}


def normalize_to_canonical(status_str: Optional[str]) -> str:
    """Normalizes database or incoming string to canonical status (OPEN, IN_PROGRESS, UNDER_REVIEW, CLOSED)."""
    if not status_str:
        return "OPEN"
    norm = status_str.strip().upper().replace(" ", "_")
    if norm in CANONICAL_TO_DB:
        return norm
    # Lookup in DB mapping
    for db_val, canon_val in DB_TO_CANONICAL.items():
        if db_val.lower() == status_str.strip().lower():
            return canon_val
    return norm


def canonical_to_db(canon_status: str) -> str:
    """Maps canonical status back to exact database Enum value."""
    norm = normalize_to_canonical(canon_status)
    return CANONICAL_TO_DB.get(norm, "Open")


# ==============================================================================
# AUTHORIZATION & CASE RESOLVER
# ==============================================================================

def get_assigned_investigator_case(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> Case:
    """
    Resolves a case by numeric ID or human-readable case string,
    enforcing strict authorization:
    - User must be authenticated
    - User must have role_id == 2 (Investigator)
    - Case.investigator_id == current_user.id
    """
    if not current_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )

    if current_user.role_id != 2:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Investigator access required"
        )

    ident_str = str(case_identifier).strip()
    if ident_str.isdigit():
        case = db.query(Case).filter(
            or_(
                Case.id == int(ident_str),
                Case.case_id == ident_str
            )
        ).first()
    else:
        case = db.query(Case).filter(
            Case.case_id.ilike(ident_str)
        ).first()

    if not case:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Case '{case_identifier}' not found"
        )

    if case.investigator_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied: You are not assigned to this case"
        )

    return case


# ==============================================================================
# SUMMARY & METRIC CALCULATION HELPERS
# ==============================================================================

def compute_case_evidence_counts(db: Session, case_id: int) -> Dict[str, Any]:
    """Calculates actual evidence metrics strictly from persisted evidence and hash records."""
    evidences = db.query(Evidence).filter(Evidence.case_id == case_id).all()
    total_evidence = len(evidences)

    if total_evidence == 0:
        return {
            "total_evidence_collected": 0,
            "evidence_analyzed": 0,
            "pending_analysis": 0,
            "integrity_issues": 0,
            "evidence_added_today": 0,
            "last_evidence_added_at": None,
            "evidences": []
        }

    ev_ids = [e.id for e in evidences]

    analyzed = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id == case_id,
        EPRAResult.analysis_status == "COMPLETE"
    ).distinct().count()

    pending_analysis = max(0, total_evidence - analyzed)

    integrity_issues = db.query(EvidenceHash).filter(
        EvidenceHash.evidence_id.in_(ev_ids),
        or_(
            EvidenceHash.tampered == True,
            EvidenceHash.hash_match == False,
            EvidenceHash.integrity_status.in_(["TAMPERED", "MISMATCH", "Tampered", "Mismatch"])
        )
    ).count()

    now_utc = datetime.now(timezone.utc)
    evidence_added_today = 0
    for e in evidences:
        if e.created_at:
            e_dt = e.created_at
            if e_dt.tzinfo is None:
                e_date = e_dt.date()
            else:
                e_date = e_dt.astimezone(timezone.utc).date()
            if e_date == now_utc.date():
                evidence_added_today += 1

    last_evidence_added_at = max((e.created_at for e in evidences if e.created_at), default=None)

    return {
        "total_evidence_collected": total_evidence,
        "evidence_analyzed": analyzed,
        "pending_analysis": pending_analysis,
        "integrity_issues": integrity_issues,
        "evidence_added_today": evidence_added_today,
        "last_evidence_added_at": last_evidence_added_at,
        "evidences": evidences
    }


def compute_case_report_status(db: Session, case: Case) -> str:
    """Derives genuine report status reusing ReportRecord architecture."""
    case_match_ids = [str(case.case_id), str(case.id)]
    reports = db.query(ReportRecord).filter(
        ReportRecord.case_id.in_(case_match_ids)
    ).order_by(ReportRecord.generated_at.desc()).all()

    final_rep = next((r for r in reports if not r.is_draft), None)
    draft_rep = next((r for r in reports if r.is_draft), None)

    if final_rep:
        return "FINAL" if case.status == "Closed" else "GENERATED"
    elif draft_rep:
        return "DRAFT"
    else:
        return "NOT_GENERATED"


def compute_module_readiness(
    db: Session,
    case: Case,
    ev_counts: Dict[str, Any],
    report_status: str
) -> Dict[str, str]:
    """
    Computes module readiness statuses for 8 forensic modules.
    Accurately supports NOT_APPLICABLE so irrelevant modules do not block progression.
    """
    evidences: List[Evidence] = ev_counts.get("evidences", [])
    total_ev = ev_counts["total_evidence_collected"]
    analyzed_ev = ev_counts["evidence_analyzed"]
    ev_ids = [e.id for e in evidences]

    # 1. Evidence Collection
    if total_ev > 0:
        ev_coll = "COMPLETED"
    else:
        ev_coll = "PENDING"

    # 2. Integrity Verification
    if total_ev == 0:
        integ_verif = "PENDING"
    else:
        verified_count = db.query(EvidenceHash).filter(
            EvidenceHash.evidence_id.in_(ev_ids),
            EvidenceHash.verified_at.isnot(None)
        ).count()
        if verified_count >= total_ev:
            integ_verif = "COMPLETED"
        elif verified_count > 0:
            integ_verif = "IN_PROGRESS"
        else:
            integ_verif = "PENDING"

    # 3. EPRA
    if total_ev == 0:
        epra_mod = "PENDING"
    elif analyzed_ev >= total_ev:
        epra_mod = "COMPLETED"
    elif analyzed_ev > 0:
        epra_mod = "IN_PROGRESS"
    else:
        epra_mod = "PENDING"

    # 4. CBIR (NOT_APPLICABLE if no image files exist)
    image_exts = {".jpg", ".jpeg", ".png", ".bmp", ".webp", ".tiff"}
    has_images = any(
        Path(e.file_name).suffix.lower() in image_exts or (e.file_type and "image" in e.file_type.lower())
        for e in evidences
    )
    if not has_images:
        cbir_mod = "NOT_APPLICABLE"
    else:
        cbir_count = db.query(CBIRResult).filter(CBIRResult.case_id == case.id).count()
        if cbir_count > 0:
            cbir_mod = "COMPLETED"
        else:
            cbir_mod = "PENDING"

    # 5. Suspect Ranking
    entity_count = db.query(PossibleEntity).filter(PossibleEntity.case_id == case.id).count()
    if entity_count > 0:
        suspect_mod = "COMPLETED"
    elif total_ev > 0 and analyzed_ev >= total_ev:
        suspect_mod = "NOT_APPLICABLE"
    else:
        suspect_mod = "PENDING"

    # 6. Relationship Analysis (NOT_APPLICABLE if <= 1 evidence item)
    if total_ev <= 1:
        rel_mod = "NOT_APPLICABLE"
    else:
        link_count = db.query(EvidenceLink).filter(EvidenceLink.case_id == case.id).count()
        if link_count > 0:
            rel_mod = "COMPLETED"
        else:
            rel_mod = "PENDING"

    # 7. Timeline Reconstruction
    ct_count = db.query(CaseTimeline).filter(CaseTimeline.case_id == case.id).count()
    cust_count = db.query(CustodyLog).filter(CustodyLog.case_id == str(case.case_id)).count()
    act_count = db.query(ActivityLog).filter(ActivityLog.case_id == str(case.case_id)).count()
    if (ct_count + cust_count + act_count) > 0:
        timeline_mod = "COMPLETED"
    else:
        timeline_mod = "PENDING"

    # 8. Final Report
    if report_status in ["FINAL", "GENERATED"]:
        report_mod = "COMPLETED"
    elif report_status == "DRAFT":
        report_mod = "IN_PROGRESS"
    else:
        report_mod = "PENDING"

    return {
        "evidence_collection": ev_coll,
        "integrity_verification": integ_verif,
        "epra": epra_mod,
        "cbir": cbir_mod,
        "suspect_ranking": suspect_mod,
        "relationship_analysis": rel_mod,
        "timeline_reconstruction": timeline_mod,
        "final_report": report_mod
    }


def compute_health_and_readiness(
    case: Case,
    ev_counts: Dict[str, Any],
    report_status: str,
    days_opened: int
) -> Tuple[str, NextStageReadinessItem]:
    """
    Computes deterministic Case Health (ON_TRACK, NEEDS_ATTENTION, BLOCKED)
    and NextStageReadiness with specific blocking issues.
    """
    canonical_st = normalize_to_canonical(case.status)
    integrity_issues = ev_counts["integrity_issues"]
    total_ev = ev_counts["total_evidence_collected"]
    pending_analysis = ev_counts["pending_analysis"]

    # 1. Case Health
    if integrity_issues > 0:
        case_health = "BLOCKED"
    elif canonical_st == "IN_PROGRESS" and pending_analysis > 0:
        case_health = "NEEDS_ATTENTION"
    elif days_opened > 30 and canonical_st not in ["CLOSED", "UNDER_REVIEW"]:
        case_health = "NEEDS_ATTENTION"
    else:
        case_health = "ON_TRACK"

    # 2. Next-Stage Readiness
    blocking_issues: List[str] = []
    ready = False
    next_stage: Optional[str] = None

    if canonical_st == "OPEN":
        next_stage = "IN_PROGRESS"
        ready = True
        blocking_issues = []

    elif canonical_st == "IN_PROGRESS":
        next_stage = "UNDER_REVIEW"
        if total_ev == 0:
            blocking_issues.append("No evidence collected for this case")
        if pending_analysis > 0:
            blocking_issues.append(f"{pending_analysis} evidence item(s) pending analysis")
        if integrity_issues > 0:
            blocking_issues.append(f"{integrity_issues} evidence item(s) have integrity issues/hash mismatches")
        ready = (len(blocking_issues) == 0)

    elif canonical_st == "UNDER_REVIEW":
        next_stage = "CLOSED"
        if report_status not in ["FINAL", "GENERATED"]:
            blocking_issues.append("Final case report not generated")
        if integrity_issues > 0:
            blocking_issues.append(f"{integrity_issues} unresolved integrity issue(s)")
        if pending_analysis > 0:
            blocking_issues.append(f"{pending_analysis} evidence item(s) pending analysis")
        ready = (len(blocking_issues) == 0)

    elif canonical_st == "CLOSED":
        next_stage = None
        ready = False
        blocking_issues = ["Case is already closed"]

    return case_health, NextStageReadinessItem(
        ready_for_next_stage=ready,
        next_recommended_stage=next_stage,
        blocking_issues=blocking_issues
    )


def compute_last_activity(db: Session, case: Case) -> Tuple[Optional[str], Optional[datetime]]:
    """Derives last activity and occurrence timestamp from CaseTimeline or Case creation."""
    latest_tl = db.query(CaseTimeline).filter(
        CaseTimeline.case_id == case.id
    ).order_by(CaseTimeline.created_at.desc(), CaseTimeline.id.desc()).first()

    if latest_tl:
        return latest_tl.event, latest_tl.created_at
    return "Case created", case.created_at


def build_case_status_summary_item(
    db: Session,
    case: Case,
    inv_name: str,
    expert_name: Optional[str]
) -> CaseStatusSummaryItem:
    """Builds a single enriched CaseStatusSummaryItem strictly from real database records."""
    ev_counts = compute_case_evidence_counts(db, case.id)
    report_status = compute_case_report_status(db, case)

    # Days since opened
    now_utc = datetime.now(timezone.utc)
    if case.created_at:
        c_dt = case.created_at
        if c_dt.tzinfo is None:
            c_date = c_dt.date()
        else:
            c_date = c_dt.astimezone(timezone.utc).date()
        days_since_opened = max(0, (now_utc.date() - c_date).days)
    else:
        days_since_opened = 0

    # Investigation progress (reusing established project algorithm)
    has_ev = ev_counts["total_evidence_collected"] > 0
    has_verif = (ev_counts["total_evidence_collected"] > 0 and ev_counts["integrity_issues"] == 0)
    has_epra = ev_counts["evidence_analyzed"] > 0
    has_rep = report_status in ["GENERATED", "FINAL"]
    investigation_progress = calculate_investigation_progress(case, has_ev, has_verif, has_epra, has_rep)

    module_readiness = compute_module_readiness(db, case, ev_counts, report_status)
    case_health, next_stage_readiness = compute_health_and_readiness(case, ev_counts, report_status, days_since_opened)
    last_act, last_act_at = compute_last_activity(db, case)

    canonical_st = normalize_to_canonical(case.status)

    return CaseStatusSummaryItem(
        id=case.id,
        case_id=case.case_id,
        case_title=case.title or f"Case #{case.case_id}",
        crime_type=case.description or "General Cyber Crime",
        priority=case.priority or "Medium",
        current_status=canonical_st,
        raw_status=case.status,
        assigned_investigator=inv_name,
        assigned_cyber_expert=expert_name,
        created_at=case.created_at,
        updated_at=case.updated_at,
        days_since_opened=days_since_opened,
        investigation_deadline=None,  # No deadline column in Case model
        investigation_progress=investigation_progress,
        total_evidence_collected=ev_counts["total_evidence_collected"],
        evidence_analyzed=ev_counts["evidence_analyzed"],
        pending_analysis=ev_counts["pending_analysis"],
        integrity_issues=ev_counts["integrity_issues"],
        evidence_added_today=ev_counts["evidence_added_today"],
        last_evidence_added_at=ev_counts["last_evidence_added_at"],
        evidence_counts=EvidenceCountsItem(
            total_evidence_collected=ev_counts["total_evidence_collected"],
            evidence_analyzed=ev_counts["evidence_analyzed"],
            pending_analysis=ev_counts["pending_analysis"],
            integrity_issues=ev_counts["integrity_issues"],
            evidence_added_today=ev_counts["evidence_added_today"],
            last_evidence_added_at=ev_counts["last_evidence_added_at"]
        ),
        report_status=report_status,
        last_activity=last_act,
        last_activity_at=last_act_at,
        case_health=case_health,
        module_readiness=module_readiness,
        next_stage_readiness=next_stage_readiness
    )


# ==============================================================================
# 1. INVESTIGATOR CASE STATUS BOARD
# ==============================================================================

def get_investigator_case_status_board(
    db: Session,
    current_user: User,
    search: Optional[str] = None,
    status_filter: Optional[str] = None,
    priority: Optional[str] = None,
    case_health_filter: Optional[str] = None,
    report_status_filter: Optional[str] = None,
    page: int = 1,
    page_size: int = 10
) -> CaseStatusBoardResponse:
    """
    Returns the complete Case Status board strictly scoped to cases assigned
    to the authenticated Investigator (Case.investigator_id == current_user.id).
    Supports Kanban columns: OPEN, IN_PROGRESS, UNDER_REVIEW, CLOSED, with full counts.
    """
    if not current_user or current_user.role_id != 2:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Investigator access required"
        )

    # Base query: strictly assigned to current investigator
    Expert = aliased(User)
    query = (
        db.query(Case, Expert.full_name.label("expert_name"))
        .outerjoin(Expert, Case.cyber_expert_id == Expert.id)
        .filter(Case.investigator_id == current_user.id)
    )

    # Filter: Search (case_id, title, description / crime_type)
    if search and search.strip():
        term = f"%{search.strip()}%"
        query = query.filter(
            or_(
                Case.case_id.ilike(term),
                Case.title.ilike(term),
                Case.description.ilike(term)
            )
        )

    # Filter: Status
    if status_filter and status_filter.strip() and status_filter.upper() != "ALL":
        target_db = canonical_to_db(status_filter)
        query = query.filter(Case.status == target_db)

    # Filter: Priority
    if priority and priority.strip() and priority.upper() != "ALL":
        query = query.filter(Case.priority.ilike(priority.strip()))

    all_assigned_cases = query.order_by(Case.updated_at.desc(), Case.id.desc()).all()

    # Pre-fetch user name
    inv_name = current_user.full_name or "Investigator"

    # Build summary items
    items: List[CaseStatusSummaryItem] = []
    for c, exp_name in all_assigned_cases:
        item = build_case_status_summary_item(db, c, inv_name, exp_name)

        # Filter: Case Health in python if requested
        if case_health_filter and case_health_filter.strip() and case_health_filter.upper() != "ALL":
            if item.case_health.upper() != case_health_filter.strip().upper():
                continue

        # Filter: Report Status in python if requested
        if report_status_filter and report_status_filter.strip() and report_status_filter.upper() != "ALL":
            if item.report_status.upper() != report_status_filter.strip().upper():
                continue

        items.append(item)

    # Aggregate counts across filtered items
    open_count = sum(1 for it in items if it.current_status == "OPEN")
    in_progress_count = sum(1 for it in items if it.current_status == "IN_PROGRESS")
    under_review_count = sum(1 for it in items if it.current_status == "UNDER_REVIEW")
    closed_count = sum(1 for it in items if it.current_status == "CLOSED")
    total_cases = len(items)

    # Build sections
    sections: Dict[str, List[CaseStatusSummaryItem]] = {
        "OPEN": [it for it in items if it.current_status == "OPEN"],
        "IN_PROGRESS": [it for it in items if it.current_status == "IN_PROGRESS"],
        "UNDER_REVIEW": [it for it in items if it.current_status == "UNDER_REVIEW"],
        "CLOSED": [it for it in items if it.current_status == "CLOSED"]
    }

    # Pagination for flat list
    safe_page = max(1, page)
    safe_size = max(1, page_size)
    total_pages = max(1, (total_cases + safe_size - 1) // safe_size) if total_cases > 0 else 1
    offset = (safe_page - 1) * safe_size
    paged_cases = items[offset: offset + safe_size]

    return CaseStatusBoardResponse(
        open_count=open_count,
        in_progress_count=in_progress_count,
        under_review_count=under_review_count,
        closed_count=closed_count,
        total_cases=total_cases,
        cases=paged_cases,
        sections=sections,
        page=safe_page,
        page_size=safe_size,
        total_pages=total_pages
    )


# ==============================================================================
# 2. CASE STATUS EXPANDED / DETAIL
# ==============================================================================

def get_investigator_case_status_detail(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> CaseStatusDetailResponse:
    """
    Returns full expanded details for a single assigned case:
    - Case Information
    - Evidence Summary
    - Progress
    - Module Readiness
    - Health & Next-Stage Readiness
    - Status History
    """
    case = get_assigned_investigator_case(db, case_identifier, current_user)

    # Assigned expert
    expert_name = None
    if case.cyber_expert_id:
        exp = db.query(User).filter(User.id == case.cyber_expert_id).first()
        if exp:
            expert_name = exp.full_name

    summary_item = build_case_status_summary_item(
        db, case, current_user.full_name or "Investigator", expert_name
    )

    # Fetch status history
    history_rows = (
        db.query(CaseStatusHistory, User.full_name.label("changer_name"))
        .outerjoin(User, CaseStatusHistory.changed_by_user_id == User.id)
        .filter(CaseStatusHistory.case_id == case.id)
        .order_by(CaseStatusHistory.changed_at.desc(), CaseStatusHistory.id.desc())
        .all()
    )

    status_history = [
        StatusHistoryItem(
            id=h.id,
            case_id=case.case_id,
            old_status=h.old_status,
            new_status=h.new_status,
            changed_by_user_id=h.changed_by_user_id,
            changed_by_name=changer_name or "Unknown",
            changed_by_role=h.changed_by_role,
            changed_at=h.changed_at,
            remark=h.remark
        )
        for h, changer_name in history_rows
    ]

    case_info = CaseInformationItem(
        id=case.id,
        case_id=case.case_id,
        title=case.title,
        description=case.description,
        crime_type=summary_item.crime_type,
        priority=summary_item.priority,
        current_status=summary_item.current_status,
        raw_status=case.status,
        assigned_investigator=summary_item.assigned_investigator,
        assigned_cyber_expert=summary_item.assigned_cyber_expert,
        created_at=case.created_at,
        updated_at=case.updated_at,
        days_since_opened=summary_item.days_since_opened,
        investigation_deadline=summary_item.investigation_deadline
    )

    return CaseStatusDetailResponse(
        case_information=case_info,
        evidence_summary=summary_item.evidence_counts,
        investigation_progress=summary_item.investigation_progress,
        module_readiness=summary_item.module_readiness,
        case_health=summary_item.case_health,
        blocking_issues=summary_item.next_stage_readiness.blocking_issues,
        next_recommended_stage=summary_item.next_stage_readiness.next_recommended_stage,
        ready_for_next_stage=summary_item.next_stage_readiness.ready_for_next_stage,
        report_status=summary_item.report_status,
        status_history=status_history
    )


# ==============================================================================
# 3. CHANGE CASE STATUS (TRANSACTIONAL TRANSITION)
# ==============================================================================

def update_case_status_by_investigator(
    db: Session,
    case_identifier: str | int,
    new_status_raw: str,
    remark: Optional[str],
    current_user: User
) -> Dict[str, Any]:
    """
    Authorizes Investigator and transitions Case.status using the strict state machine.
    Updates the SAME Case.status column transactionally with CaseStatusHistory & CaseTimeline.
    """
    case = get_assigned_investigator_case(db, case_identifier, current_user)

    curr_canon = normalize_to_canonical(case.status)

    target_canon = normalize_to_canonical(new_status_raw)
    if target_canon not in CANONICAL_TO_DB:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid status '{new_status_raw}'. Allowed canonical values: OPEN, IN_PROGRESS, UNDER_REVIEW, CLOSED."
        )

    target_db = canonical_to_db(target_canon)

    if curr_canon == target_canon:
        return {
            "message": "Case status unchanged",
            "case_id": case.case_id,
            "previous_status": curr_canon,
            "current_status": target_canon,
            "changed_at": datetime.now(timezone.utc),
            "remark": remark
        }

    # Validate transition state machine
    allowed_next = ALLOWED_TRANSITIONS.get(curr_canon, [])
    if target_canon not in allowed_next:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Transition from {curr_canon} to {target_canon} is not allowed. "
                f"Allowed transitions from {curr_canon}: {', '.join(allowed_next) if allowed_next else 'None (terminal state)'}."
            )
        )

    old_db_status = case.status

    try:
        # Update SAME Case.status field
        case.status = target_db

        # 1. Status History record
        history_record = CaseStatusHistory(
            case_id=case.id,
            old_status=curr_canon,
            new_status=target_canon,
            changed_by_user_id=current_user.id,
            changed_by_role="Investigator",
            remark=remark
        )
        db.add(history_record)

        # 2. Timeline event for Admin & audit trail
        create_timeline_event(
            db=db,
            case_id=case.id,
            event=f"Case status changed from {old_db_status} to {target_db}" + (f": {remark}" if remark else ""),
            performed_by=current_user.id,
            performed_by_role="Investigator"
        )

        # 3. Targeted milestone notification to Admin if moving to Under Review or Closed
        if target_db in ["Under Review", "Closed"]:
            creator = db.query(User).filter(User.id == case.created_by).first()
            cell_id = creator.cyber_cell_id if creator else current_user.cyber_cell_id
            if cell_id:
                admins = db.query(User).filter(
                    User.role_id == 1,
                    User.cyber_cell_id == cell_id,
                    User.is_active == True
                ).all()
                for admin in admins:
                    if admin.id != current_user.id:
                        create_notification(
                            db=db,
                            title=f"Case Milestone: {target_db}",
                            message=f"Case {case.case_id} has moved to {target_db} by Investigator {current_user.full_name}.",
                            notification_type="CASE_STATUS",
                            user_id=admin.id,
                            cyber_cell_id=None
                        )

        # 4. Notify assigned Cyber Expert
        if case.cyber_expert_id and case.cyber_expert_id != current_user.id:
            create_notification(
                db=db,
                title="Case Status Updated",
                message=f"Case {case.case_id} status changed from {old_db_status} to {target_db}.",
                notification_type="CASE_STATUS",
                user_id=case.cyber_expert_id,
                cyber_cell_id=None
            )

        # 5. Notify assigned Investigator (if changed by another actor)
        if case.investigator_id and case.investigator_id != current_user.id:
            create_notification(
                db=db,
                title="Case Status Updated",
                message=f"Case {case.case_id} status changed from {old_db_status} to {target_db}.",
                notification_type="CASE_STATUS",
                user_id=case.investigator_id,
                cyber_cell_id=None
            )

        db.commit()
        db.refresh(case)
        db.refresh(history_record)

    except HTTPException:
        db.rollback()
        raise
    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to update case status transactionally: {str(e)}"
        )

    return {
        "message": "Case status updated successfully",
        "case_id": case.case_id,
        "previous_status": curr_canon,
        "current_status": target_canon,
        "changed_at": history_record.changed_at,
        "remark": remark
    }


# ==============================================================================
# 4. STATUS HISTORY LIST
# ==============================================================================

def get_investigator_case_status_history(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> List[StatusHistoryItem]:
    """Retrieves full chronological status history for the case in newest-first order."""
    case = get_assigned_investigator_case(db, case_identifier, current_user)

    history_rows = (
        db.query(CaseStatusHistory, User.full_name.label("changer_name"))
        .outerjoin(User, CaseStatusHistory.changed_by_user_id == User.id)
        .filter(CaseStatusHistory.case_id == case.id)
        .order_by(CaseStatusHistory.changed_at.desc(), CaseStatusHistory.id.desc())
        .all()
    )

    return [
        StatusHistoryItem(
            id=h.id,
            case_id=case.case_id,
            old_status=h.old_status,
            new_status=h.new_status,
            changed_by_user_id=h.changed_by_user_id,
            changed_by_name=changer_name or "Unknown",
            changed_by_role=h.changed_by_role,
            changed_at=h.changed_at,
            remark=h.remark
        )
        for h, changer_name in history_rows
    ]
