import mimetypes
from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple
from datetime import datetime
from fastapi import HTTPException, status
from sqlalchemy.orm import Session, aliased
from sqlalchemy import or_, func

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from models.notification import Notification
from models.case_timeline import CaseTimeline
from models.evidence_record import EvidenceRecord
from services.timeline_service import TimelineService

from schemas.investigator_dashboard import (
    InvestigatorDashboardStats,
    CaseRequiringAttentionItem,
    InvestigatorEvidenceStatusResponse,
    CaseStatusDistributionResponse,
    InvestigatorCaseItem,
    InvestigatorMyCasesPage,
    TeamMemberItem,
    CaseDetailItem,
    CaseStatisticsItem,
    TimelineActivityItem,
    CaseOverviewResponse,
    CaseEvidenceSummaryResponse,
    InvestigatorEvidenceRepositoryItem,
    InvestigatorEvidenceRepositoryPage,
    InvestigatorEvidenceDetailResponse
)


# ==============================================================================
# 1. INVESTIGATOR DASHBOARD STATS (7 CARDS)
# ==============================================================================

def get_investigator_dashboard_stats(
    db: Session,
    current_user: User
) -> InvestigatorDashboardStats:
    """
    Computes all 7 summary card values derived strictly from genuine TiDB records
    scoped exclusively to cases assigned to the current investigator (Case.investigator_id == current_user.id).
    """
    # 1. Total Assigned Cases
    assigned_query = db.query(Case).filter(Case.investigator_id == current_user.id)
    total_assigned_cases = assigned_query.count()

    # 2. Active Cases: Open + In Progress + Under Review
    active_cases = assigned_query.filter(
        Case.status.in_(["Open", "In Progress", "Under Review"])
    ).count()

    # 7. Completed Cases: Closed
    completed_cases = assigned_query.filter(
        Case.status == "Closed"
    ).count()

    # Fetch assigned case IDs
    assigned_case_ids = [
        c.id for c in db.query(Case.id).filter(Case.investigator_id == current_user.id).all()
    ]

    if not assigned_case_ids:
        return InvestigatorDashboardStats(
            total_assigned_cases=0,
            active_cases=0,
            evidence_uploaded=0,
            evidence_pending_analysis=0,
            new_analysis_results=0,
            cases_requiring_attention=0,
            completed_cases=0
        )

    # 3. Evidence Uploaded: All evidence belonging to investigator's assigned cases
    evidence_uploaded = db.query(Evidence).filter(
        Evidence.case_id.in_(assigned_case_ids)
    ).count()

    # 4. Evidence Pending Analysis:
    # Analyzed = Evidence items with an EPRAResult record where analysis_status == 'COMPLETE'
    analyzed_count = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id.in_(assigned_case_ids),
        EPRAResult.analysis_status == "COMPLETE"
    ).distinct().count()

    evidence_pending_analysis = max(0, evidence_uploaded - analyzed_count)

    # 5. New Analysis Results:
    # Deterministic Rule:
    # First check unread analysis notifications for this user (Notification.is_read == False).
    # If unread analysis notifications exist, use that count.
    # Otherwise, count completed EPRA evidence items in active assigned cases (status != 'Closed').
    unread_analysis_notifs = db.query(Notification).filter(
        Notification.user_id == current_user.id,
        Notification.is_read == False,
        or_(
            Notification.type.ilike("%analysis%"),
            Notification.type.ilike("%epra%"),
            Notification.title.ilike("%analysis%"),
            Notification.title.ilike("%epra%")
        )
    ).count()

    if unread_analysis_notifs > 0:
        new_analysis_results = unread_analysis_notifs
    else:
        active_case_ids = [
            c.id for c in db.query(Case.id).filter(
                Case.investigator_id == current_user.id,
                Case.status.in_(["Open", "In Progress", "Under Review"])
            ).all()
        ]
        if active_case_ids:
            new_analysis_results = db.query(EPRAResult.evidence_id).filter(
                EPRAResult.case_id.in_(active_case_ids),
                EPRAResult.analysis_status == "COMPLETE"
            ).distinct().count()
        else:
            new_analysis_results = 0

    # 6. Cases Requiring Attention:
    attention_cases = get_cases_requiring_attention(db, current_user)
    cases_requiring_attention = len(attention_cases)

    return InvestigatorDashboardStats(
        total_assigned_cases=total_assigned_cases,
        active_cases=active_cases,
        evidence_uploaded=evidence_uploaded,
        evidence_pending_analysis=evidence_pending_analysis,
        new_analysis_results=new_analysis_results,
        cases_requiring_attention=cases_requiring_attention,
        completed_cases=completed_cases
    )


# ==============================================================================
# 2. CASES REQUIRING ATTENTION
# ==============================================================================

def get_cases_requiring_attention(
    db: Session,
    current_user: User
) -> List[CaseRequiringAttentionItem]:
    """
    Identifies assigned cases requiring immediate investigator attention based strictly
    on genuine database conditions:
    1. Integrity / hash mismatch or tampered evidence.
    2. Critical EPRA evidence prioritized by analysis.
    3. High or Critical priority case in Open state.
    Consolidates multiple reasons into a single case row to avoid duplicates.
    """
    assigned_cases = db.query(Case).filter(
        Case.investigator_id == current_user.id
    ).all()

    if not assigned_cases:
        return []

    case_map = {c.id: c for c in assigned_cases}
    assigned_case_ids = list(case_map.keys())

    # Map of case_id -> list of distinct reason strings
    reasons_by_case: Dict[int, List[str]] = {cid: [] for cid in assigned_case_ids}

    # Condition 1: Hash mismatch or tampered evidence
    tampered_evidence_rows = (
        db.query(Evidence.case_id, Evidence.file_name, EvidenceHash.integrity_status)
        .join(EvidenceHash, Evidence.id == EvidenceHash.evidence_id)
        .filter(
            Evidence.case_id.in_(assigned_case_ids),
            or_(
                EvidenceHash.tampered == True,
                EvidenceHash.hash_match == False,
                EvidenceHash.integrity_status.in_(["TAMPERED", "MISMATCH", "Tampered", "Mismatch"])
            )
        )
        .all()
    )
    for cid, file_name, status_text in tampered_evidence_rows:
        reason = f"Evidence integrity compromised ({file_name})"
        if reason not in reasons_by_case[cid]:
            reasons_by_case[cid].append(reason)

    # Condition 2: Critical priority EPRA evidence
    critical_epra_rows = (
        db.query(EPRAResult.case_id, func.count(EPRAResult.id).label("crit_count"))
        .filter(
            EPRAResult.case_id.in_(assigned_case_ids),
            EPRAResult.priority.ilike("Critical")
        )
        .group_by(EPRAResult.case_id)
        .all()
    )
    for cid, count in critical_epra_rows:
        reason = f"Critical EPRA evidence identified ({count} item{'s' if count > 1 else ''})"
        if reason not in reasons_by_case[cid]:
            reasons_by_case[cid].append(reason)

    # Condition 3: High or Critical priority case pending action (status == 'Open')
    for c in assigned_cases:
        if c.priority in ["High", "Critical"] and c.status == "Open":
            reason = f"{c.priority} priority case pending investigation"
            if reason not in reasons_by_case[c.id]:
                reasons_by_case[c.id].append(reason)

    # Filter cases that triggered at least one reason
    attention_items: List[CaseRequiringAttentionItem] = []
    priority_order = {"Critical": 1, "High": 2, "Medium": 3, "Low": 4}

    for cid, reasons in reasons_by_case.items():
        if reasons:
            c = case_map[cid]
            attention_items.append(
                CaseRequiringAttentionItem(
                    id=c.id,
                    case_id=c.case_id,
                    title=c.title,
                    priority=c.priority,
                    status=c.status,
                    reason="; ".join(reasons),
                    updated_at=c.updated_at or c.created_at
                )
            )

    # Sort by priority severity, then updated_at descending
    attention_items.sort(
        key=lambda x: (priority_order.get(x.priority, 5), -(x.updated_at.timestamp() if x.updated_at else 0))
    )

    return attention_items


# ==============================================================================
# 3. EVIDENCE STATUS BREAKDOWN (ALL ASSIGNED CASES)
# ==============================================================================

def get_evidence_status(
    db: Session,
    current_user: User
) -> InvestigatorEvidenceStatusResponse:
    """
    Returns genuine evidence status metrics across only the investigator's assigned cases.
    Distinguishes clearly between analysis state (Analyzed vs Pending Analysis)
    and integrity state (Verified vs Tampered vs Pending Verification).
    """
    assigned_case_ids = [
        c.id for c in db.query(Case.id).filter(Case.investigator_id == current_user.id).all()
    ]

    if not assigned_case_ids:
        return InvestigatorEvidenceStatusResponse(
            total_evidence=0,
            analyzed=0,
            pending_analysis=0,
            integrity_verified=0,
            integrity_issue=0,
            pending_verification=0,
            analysis_breakdown={
                "Analyzed": 0,
                "Pending Analysis": 0
            },
            integrity_breakdown={
                "Verified": 0,
                "Tampered / Mismatch": 0,
                "Pending Verification": 0
            }
        )

    evidences = db.query(Evidence).filter(
        Evidence.case_id.in_(assigned_case_ids)
    ).all()
    total_evidence = len(evidences)
    ev_ids = [e.id for e in evidences]

    if not ev_ids:
        return InvestigatorEvidenceStatusResponse(
            total_evidence=0,
            analyzed=0,
            pending_analysis=0,
            integrity_verified=0,
            integrity_issue=0,
            pending_verification=0,
            analysis_breakdown={
                "Analyzed": 0,
                "Pending Analysis": 0
            },
            integrity_breakdown={
                "Verified": 0,
                "Tampered / Mismatch": 0,
                "Pending Verification": 0
            }
        )

    # Analysis metrics: EPRAResult
    analyzed = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id.in_(assigned_case_ids),
        EPRAResult.analysis_status == "COMPLETE"
    ).distinct().count()

    pending_analysis = max(0, total_evidence - analyzed)

    # Integrity metrics: EvidenceHash
    hashes = db.query(EvidenceHash).filter(
        EvidenceHash.evidence_id.in_(ev_ids)
    ).all()
    hash_by_ev = {h.evidence_id: h for h in hashes}

    integrity_verified = 0
    integrity_issue = 0
    pending_verification = 0

    for eid in ev_ids:
        h = hash_by_ev.get(eid)
        if not h:
            pending_verification += 1
        elif h.tampered is True or h.hash_match is False or (
            h.integrity_status and h.integrity_status.upper() in ["TAMPERED", "MISMATCH"]
        ):
            integrity_issue += 1
        elif h.hash_match is True or (
            h.integrity_status and h.integrity_status.upper() in ["MATCH", "VERIFIED"]
        ):
            integrity_verified += 1
        else:
            pending_verification += 1

    return InvestigatorEvidenceStatusResponse(
        total_evidence=total_evidence,
        analyzed=analyzed,
        pending_analysis=pending_analysis,
        integrity_verified=integrity_verified,
        integrity_issue=integrity_issue,
        pending_verification=pending_verification,
        analysis_breakdown={
            "Analyzed": analyzed,
            "Pending Analysis": pending_analysis
        },
        integrity_breakdown={
            "Verified": integrity_verified,
            "Tampered / Mismatch": integrity_issue,
            "Pending Verification": pending_verification
        }
    )


# ==============================================================================
# 4. CASE STATUS DISTRIBUTION
# ==============================================================================

def get_case_status_distribution(
    db: Session,
    current_user: User
) -> CaseStatusDistributionResponse:
    """
    Returns exact case counts by status (Open, In Progress, Under Review, Closed)
    for the investigator's assigned cases.
    """
    assigned_query = db.query(Case).filter(Case.investigator_id == current_user.id)

    open_count = assigned_query.filter(Case.status == "Open").count()
    in_progress = assigned_query.filter(Case.status == "In Progress").count()
    under_review = assigned_query.filter(Case.status == "Under Review").count()
    closed = assigned_query.filter(Case.status == "Closed").count()
    total = open_count + in_progress + under_review + closed

    return CaseStatusDistributionResponse(
        open=open_count,
        in_progress=in_progress,
        under_review=under_review,
        closed=closed,
        total=total
    )


# ==============================================================================
# 5. MY ASSIGNED CASES
# ==============================================================================

def get_investigator_my_cases(
    db: Session,
    current_user: User,
    search: Optional[str] = None,
    status: Optional[str] = None,
    priority: Optional[str] = None,
    cyber_expert_id: Optional[int] = None,
    start_date: Optional[str] = None,
    end_date: Optional[str] = None,
    page: int = 1,
    limit: int = 10
) -> InvestigatorMyCasesPage:
    """
    Returns paginated assigned cases for the investigator with search, status, priority,
    and cyber expert filters.
    Computes analysis progress dynamically:
    analysis_progress = (analyzed_evidence / total_evidence) * 100 if total_evidence > 0 else 0.0
    """
    CyberExpert = aliased(User)

    query = (
        db.query(Case, CyberExpert.full_name.label("cyber_expert_name"))
        .outerjoin(CyberExpert, Case.cyber_expert_id == CyberExpert.id)
        .filter(Case.investigator_id == current_user.id)
    )

    # Search filter across case_id, title, description
    if search and search.strip():
        term = f"%{search.strip()}%"
        query = query.filter(
            or_(
                Case.case_id.ilike(term),
                Case.title.ilike(term),
                Case.description.ilike(term)
            )
        )

    # Status filter
    if status and status.strip():
        query = query.filter(Case.status == status.strip())

    # Priority filter
    if priority and priority.strip():
        query = query.filter(Case.priority == priority.strip())

    # Cyber Expert filter
    if cyber_expert_id:
        query = query.filter(Case.cyber_expert_id == cyber_expert_id)

    # Optional date filters
    if start_date:
        try:
            dt_start = datetime.fromisoformat(start_date.replace("Z", "+00:00"))
            query = query.filter(Case.created_at >= dt_start)
        except Exception:
            pass

    if end_date:
        try:
            dt_end = datetime.fromisoformat(end_date.replace("Z", "+00:00"))
            query = query.filter(Case.created_at <= dt_end)
        except Exception:
            pass

    # Total matching cases
    total = query.count()

    # Pagination
    offset = (page - 1) * limit
    results = (
        query
        .order_by(Case.updated_at.desc(), Case.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    case_items: List[InvestigatorCaseItem] = []

    for case, expert_name in results:
        cid = case.id

        # Total evidence for this case
        total_ev = db.query(Evidence).filter(Evidence.case_id == cid).count()

        # Analyzed evidence for this case
        analyzed_ev = db.query(EPRAResult.evidence_id).filter(
            EPRAResult.case_id == cid,
            EPRAResult.analysis_status == "COMPLETE"
        ).distinct().count()

        pending_ev = max(0, total_ev - analyzed_ev)

        # Analysis progress percentage
        if total_ev > 0:
            analysis_progress = round((analyzed_ev / total_ev) * 100.0, 2)
        else:
            analysis_progress = 0.0

        case_items.append(
            InvestigatorCaseItem(
                id=case.id,
                case_id=case.case_id,
                title=case.title,
                description=case.description,
                priority=case.priority,
                status=case.status,
                assigned_cyber_expert=expert_name,
                evidence_count=total_ev,
                analyzed_evidence_count=analyzed_ev,
                pending_analysis_count=pending_ev,
                analysis_progress=analysis_progress,
                created_at=case.created_at,
                updated_at=case.updated_at
            )
        )

    return InvestigatorMyCasesPage(
        total=total,
        page=page,
        limit=limit,
        cases=case_items
    )


# ==============================================================================
# 6. INVESTIGATOR VIEW CASE: CASE OVERVIEW
# ==============================================================================

def get_investigator_assigned_case(
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


def get_investigator_case_overview(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> CaseOverviewResponse:
    """
    Returns full Case Overview information for the assigned investigator:
    - Case metadata (genuine Case.description; no fake crime_type)
    - Assigned investigator & cyber expert
    - Key statistics (total, analyzed, pending, high priority, progress percentage)
    - Genuine recent activity from CaseTimeline and TimelineService
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)

    # 1. Assigned Investigator
    inv_user = db.query(User).filter(User.id == case.investigator_id).first()
    assigned_investigator = TeamMemberItem(
        id=inv_user.id if inv_user else current_user.id,
        name=inv_user.full_name if inv_user else current_user.full_name,
        email=inv_user.email if inv_user else current_user.email,
        role="Investigator"
    )

    # 2. Assigned Cyber Expert
    assigned_cyber_expert = None
    if case.cyber_expert_id:
        exp_user = db.query(User).filter(User.id == case.cyber_expert_id).first()
        if exp_user:
            assigned_cyber_expert = TeamMemberItem(
                id=exp_user.id,
                name=exp_user.full_name,
                email=exp_user.email,
                role="Cyber Expert"
            )

    # 3. Statistics
    total_evidence = db.query(Evidence).filter(Evidence.case_id == case.id).count()
    analyzed_evidence = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id == case.id,
        EPRAResult.analysis_status == "COMPLETE"
    ).distinct().count()
    pending_analysis = max(0, total_evidence - analyzed_evidence)
    high_priority_evidence = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id == case.id,
        EPRAResult.priority.in_(["High", "Critical", "HIGH", "CRITICAL"])
    ).distinct().count()

    # Progress rule: analyzed / total * 100 or 0.0 if zero evidence
    if total_evidence > 0:
        investigation_progress = round((analyzed_evidence / total_evidence) * 100.0, 2)
    else:
        investigation_progress = 0.0

    statistics = CaseStatisticsItem(
        total_evidence=total_evidence,
        analyzed_evidence=analyzed_evidence,
        pending_analysis=pending_analysis,
        high_priority_evidence=high_priority_evidence,
        investigation_progress=investigation_progress
    )

    # 4. Recent Activity: Derived strictly from genuine database records
    timeline_items: List[TimelineActivityItem] = []
    seen_keys = set()

    # Source A: CaseTimeline
    ct_entries = db.query(CaseTimeline).filter(
        CaseTimeline.case_id == case.id
    ).order_by(CaseTimeline.created_at.desc()).limit(20).all()

    user_cache = {}
    for ct in ct_entries:
        actor_name = None
        if ct.performed_by:
            if ct.performed_by not in user_cache:
                u = db.query(User).filter(User.id == ct.performed_by).first()
                user_cache[ct.performed_by] = u.full_name if u else None
            actor_name = user_cache[ct.performed_by]

        key = (ct.event, ct.created_at.isoformat() if ct.created_at else "")
        if key not in seen_keys:
            seen_keys.add(key)
            timeline_items.append(
                TimelineActivityItem(
                    id=f"ct_{ct.id}",
                    event=ct.event,
                    actor_name=actor_name,
                    role=ct.performed_by_role,
                    timestamp=ct.created_at
                )
            )

    # Source B: Custody / Activity logs via TimelineService
    try:
        audit_timeline = TimelineService.build_case_timeline(db, str(case.case_id))
        for at in audit_timeline:
            dt_str = at.get("timestamp")
            dt = datetime.fromisoformat(dt_str.replace("Z", "+00:00")) if dt_str else (case.updated_at or case.created_at)
            event_text = at.get("description") or at.get("event_type")
            key = (event_text, dt_str)
            if key not in seen_keys:
                seen_keys.add(key)
                timeline_items.append(
                    TimelineActivityItem(
                        id=f"tl_{at.get('step', at.get('sort_id'))}",
                        event=event_text,
                        actor_name=at.get("actor"),
                        role=None,
                        timestamp=dt
                    )
                )
    except Exception:
        pass

    # Baseline event if no timeline entries exist yet
    if not timeline_items:
        timeline_items.append(
            TimelineActivityItem(
                id=f"case_created_{case.id}",
                event=f"Case initialized: {case.title} ({case.case_id})",
                actor_name=inv_user.full_name if inv_user else None,
                role="Investigator",
                timestamp=case.created_at
            )
        )

    # Sort descending by timestamp
    timeline_items.sort(key=lambda x: -(x.timestamp.timestamp() if x.timestamp else 0))

    case_detail = CaseDetailItem(
        id=case.id,
        case_id=case.case_id,
        title=case.title,
        description=case.description,
        priority=case.priority,
        status=case.status,
        created_at=case.created_at,
        updated_at=case.updated_at
    )

    return CaseOverviewResponse(
        case=case_detail,
        assigned_investigator=assigned_investigator,
        assigned_cyber_expert=assigned_cyber_expert,
        statistics=statistics,
        recent_activity=timeline_items[:20]
    )


# ==============================================================================
# 7. INVESTIGATOR VIEW CASE: EVIDENCE MANAGEMENT SUMMARY
# ==============================================================================

def get_investigator_case_evidence_summary(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> CaseEvidenceSummaryResponse:
    """
    Returns evidence summary metrics strictly for the selected assigned case:
    - Total evidence
    - Analyzed evidence (EPRAResult COMPLETE)
    - Pending analysis (Total - Analyzed)
    - Integrity issues (tampered == True, hash_match == False, or status TAMPERED/MISMATCH)
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)

    evidences = db.query(Evidence).filter(Evidence.case_id == case.id).all()
    total_evidence = len(evidences)
    if total_evidence == 0:
        return CaseEvidenceSummaryResponse(
            total_evidence=0,
            analyzed=0,
            pending_analysis=0,
            integrity_issues=0
        )

    ev_ids = [e.id for e in evidences]

    analyzed = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id == case.id,
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

    return CaseEvidenceSummaryResponse(
        total_evidence=total_evidence,
        analyzed=analyzed,
        pending_analysis=pending_analysis,
        integrity_issues=integrity_issues
    )


# ==============================================================================
# 8. INVESTIGATOR VIEW CASE: EVIDENCE REPOSITORY LIST
# ==============================================================================

def get_investigator_case_evidence_repository(
    db: Session,
    case_identifier: str | int,
    current_user: User,
    search: Optional[str] = None,
    file_type: Optional[str] = None,
    analysis_status: Optional[str] = None,
    priority: Optional[str] = None,
    page: int = 1,
    limit: int = 10
) -> InvestigatorEvidenceRepositoryPage:
    """
    Returns paginated evidence repository items for the assigned case with filters:
    - search (by evidence_id, file_name, or current_hash)
    - file_type
    - analysis_status (e.g. COMPLETE, Pending)
    - priority (Critical, High, Medium, Low)
    Note: Unanalyzed items display "Pending" without creating fake database records.
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)

    query = (
        db.query(Evidence, EvidenceHash, EPRAResult)
        .outerjoin(EvidenceHash, Evidence.id == EvidenceHash.evidence_id)
        .outerjoin(EPRAResult, Evidence.id == EPRAResult.evidence_id)
        .filter(Evidence.case_id == case.id)
    )

    # Search filter
    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        query = query.filter(
            or_(
                Evidence.evidence_id.ilike(s),
                Evidence.file_name.ilike(s),
                EvidenceHash.current_hash.ilike(s)
            )
        )

    # File type filter
    if isinstance(file_type, str) and file_type.strip():
        query = query.filter(Evidence.file_type.ilike(file_type.strip()))

    # Analysis status filter
    if isinstance(analysis_status, str) and analysis_status.strip():
        ast = analysis_status.strip().upper()
        if ast == "PENDING":
            # Either no EPRAResult or status is not COMPLETE
            query = query.filter(
                or_(
                    EPRAResult.id == None,
                    EPRAResult.analysis_status != "COMPLETE"
                )
            )
        elif ast in ["COMPLETE", "COMPLETED"]:
            query = query.filter(EPRAResult.analysis_status == "COMPLETE")
        else:
            query = query.filter(EPRAResult.analysis_status.ilike(f"%{analysis_status.strip()}%"))

    # Priority filter
    if isinstance(priority, str) and priority.strip():
        query = query.filter(EPRAResult.priority.ilike(priority.strip()))

    total = query.count()

    offset = (page - 1) * limit
    results = (
        query
        .order_by(Evidence.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    items: List[InvestigatorEvidenceRepositoryItem] = []
    for ev, h, epra in results:
        # Fallback display values without inserting fake DB records
        if epra:
            ast = epra.analysis_status or "COMPLETE"
            prio = epra.priority
            score = epra.epra_score
            rank = epra.rank
        else:
            ast = "Pending"
            prio = None
            score = None
            rank = None

        integrity_status = h.integrity_status if h and h.integrity_status else "Unknown"
        current_hash = h.current_hash if h else None

        items.append(
            InvestigatorEvidenceRepositoryItem(
                id=ev.id,
                evidence_id=ev.evidence_id,
                file_name=ev.file_name,
                file_type=ev.file_type,
                file_size=ev.file_size,
                uploaded_on=ev.created_at,
                current_hash=current_hash,
                integrity_status=integrity_status,
                analysis_status=ast,
                priority=prio,
                epra_score=score,
                rank=rank
            )
        )

    return InvestigatorEvidenceRepositoryPage(
        total=total,
        page=page,
        limit=limit,
        items=items
    )


# ==============================================================================
# 9. INVESTIGATOR VIEW CASE: SINGLE EVIDENCE DETAILS
# ==============================================================================

def get_investigator_evidence_detail(
    db: Session,
    case_identifier: str | int,
    evidence_identifier: str | int,
    current_user: User
) -> InvestigatorEvidenceDetailResponse:
    """
    Returns single evidence detail integrating:
    - Core Evidence attributes
    - EvidenceHash verification results
    - EPRAResult priorities, risk factors, and analysis status
    - Deepak's EvidenceRecord metadata timestamps and MIME info
    - Pure read-only view for investigator
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)

    ident_str = str(evidence_identifier).strip()
    if ident_str.isdigit():
        evidence = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            or_(
                Evidence.id == int(ident_str),
                Evidence.evidence_id == ident_str
            )
        ).first()
    else:
        evidence = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            Evidence.evidence_id.ilike(ident_str)
        ).first()

    if not evidence:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Evidence '{evidence_identifier}' not found for this case"
        )

    # 1. EvidenceHash
    h = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == evidence.id).first()

    # 2. EPRAResult
    epra = db.query(EPRAResult).filter(EPRAResult.evidence_id == evidence.id).first()

    # 3. EvidenceRecord (Deepak's metadata)
    er = db.query(EvidenceRecord).filter(
        or_(
            EvidenceRecord.external_evidence_id == (evidence.evidence_id or str(evidence.id)),
            EvidenceRecord.id == evidence.id
        )
    ).first()

    # Verified by user name
    verified_by_name = None
    if h and h.verified_by:
        v_user = db.query(User).filter(User.id == h.verified_by).first()
        if v_user:
            verified_by_name = v_user.full_name

    # Uploaded by: default to assigned investigator or timeline event
    uploaded_by = current_user.full_name

    # EPRA risk factors
    risk_factors = None
    if epra:
        risk_factors = {
            "authenticity_risk": epra.authenticity_risk,
            "context_intelligence": epra.context_intelligence,
            "behaviour_intelligence": epra.behaviour_intelligence,
            "semantic_intelligence": epra.semantic_intelligence,
            "investigative_intelligence": epra.investigative_intelligence
        }

    # Metadata dictionary
    metadata_dict = None
    if er:
        metadata_dict = {
            "mime_type": er.mime_type,
            "mime_type_source": er.mime_type_source,
            "file_extension": er.file_extension,
            "file_size_bytes": er.file_size_bytes,
            "filesystem_ctime": er.filesystem_ctime,
            "filesystem_mtime": er.filesystem_mtime,
            "created_at": er.created_at.isoformat() if er.created_at else None,
            "created_at_source": er.created_at_source,
            "modified_at": er.modified_at.isoformat() if er.modified_at else None,
            "modified_at_source": er.modified_at_source,
            "accessed_at": er.accessed_at.isoformat() if er.accessed_at else None,
            "accessed_at_source": er.accessed_at_source,
            "notes": er.notes,
            "processing_status": er.processing_status
        }

    return InvestigatorEvidenceDetailResponse(
        id=evidence.id,
        evidence_id=evidence.evidence_id,
        file_name=evidence.file_name,
        file_type=evidence.file_type,
        file_size=evidence.file_size,
        uploaded_on=evidence.created_at,
        uploaded_by=uploaded_by,
        current_hash=h.current_hash if h else None,
        original_hash=h.original_hash if h else None,
        hash_match=h.hash_match if h else None,
        tampered=h.tampered if h else None,
        integrity_status=h.integrity_status if h else "Unknown",
        verification_date=h.verified_at if h else None,
        verified_by=verified_by_name,
        analysis_status=epra.analysis_status if epra else "Pending",
        priority=epra.priority if epra else None,
        epra_score=epra.epra_score if epra else None,
        rank=epra.rank if epra else None,
        ipi=epra.ipi if epra else None,
        risk_factors=risk_factors,
        pending_external_inputs=epra.pending_external_inputs if epra else None,
        metadata=metadata_dict
    )


# ==============================================================================
# 10. INVESTIGATOR VIEW CASE: SECURE EVIDENCE DOWNLOAD & PREVIEW
# ==============================================================================

def get_investigator_evidence_file(
    db: Session,
    case_identifier: str | int,
    evidence_identifier: str | int,
    current_user: User,
    for_preview: bool = False
) -> Tuple[Path, str, str]:
    """
    Safely resolves the physical evidence file from disk for download or preview:
    - Enforces assigned investigator case authorization
    - Prevents path traversal outside uploads/evidence directory
    - Returns 404 if file does not exist on disk
    - For preview, ensures format is previewable, returning 400 for non-previewable files
    Returns (resolved_file_path, file_name, mime_type).
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)

    ident_str = str(evidence_identifier).strip()
    if ident_str.isdigit():
        evidence = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            or_(
                Evidence.id == int(ident_str),
                Evidence.evidence_id == ident_str
            )
        ).first()
    else:
        evidence = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            Evidence.evidence_id.ilike(ident_str)
        ).first()

    if not evidence:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Evidence '{evidence_identifier}' not found for this case"
        )

    raw_path = Path(evidence.file_path)
    file_path = raw_path.resolve() if raw_path.is_absolute() else (Path.cwd() / raw_path).resolve()
    base_upload_dir = (Path.cwd() / "uploads" / "evidence").resolve()

    # Path traversal protection: file must be located inside base_upload_dir
    try:
        file_path.relative_to(base_upload_dir)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access denied: Invalid file path traversal"
        )

    if not file_path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Evidence file not found on disk"
        )

    mime_type, _ = mimetypes.guess_type(evidence.file_name)
    mime_type = mime_type or "application/octet-stream"

    if for_preview:
        is_image = mime_type.startswith("image/")
        is_video = mime_type.startswith("video/")
        is_audio = mime_type.startswith("audio/")
        is_pdf = mime_type == "application/pdf"
        is_text = mime_type.startswith("text/") or mime_type in ["application/json", "application/xml"]

        ext = file_path.suffix.lower().lstrip(".")
        non_previewable_exts = {"zip", "rar", "7z", "tar", "gz", "exe", "bin", "iso", "dmg", "dll"}

        if ext in non_previewable_exts or not (is_image or is_video or is_audio or is_pdf or is_text):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Preview is not supported for file format '{evidence.file_type}'. Please download the file instead."
            )

    return file_path, evidence.file_name, mime_type

