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
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.report_record import ReportRecord
from models.cbir_result import CBIRResult
from models.evidence_link import EvidenceLink
from models.current_custody import CurrentCustodyInfo
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
    InvestigatorEvidenceDetailResponse,
    AnalysisProgressSummaryResponse,
    EvidenceAnalysisItem,
    EvidenceAnalysisPage,
    EPRAPriorityDistributionResponse,
    PendingAnalysisItem,
    PendingAnalysisResponse,
    InvestigatorAnalysisDetailResponse,
    RelationshipNodeDetailResponse,
    InvestigatorCaseActivitySummaryResponse,
    InvestigatorCaseActivityItem,
    InvestigatorCaseActivityPage,
    InvestigatorActivityDetailResponse
)
from schemas.relationship_graph import GraphResponse
from services.relationship_graph_service import RelationshipGraphService


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


# ==============================================================================
# 11. INVESTIGATOR VIEW CASE: ANALYSIS PROGRESS TAB
# ==============================================================================

def get_investigator_analysis_summary(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> AnalysisProgressSummaryResponse:
    """
    Returns genuine selected-case EPRA analysis summary metrics for the assigned investigator:
    - total_evidence
    - analyzed_evidence (EPRAResult COMPLETE)
    - pending_analysis
    - partial_analysis (EPRAResult PARTIAL / PENDING INPUTS)
    - high_critical_evidence
    - overall_analysis_progress
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)
    total_evidence = db.query(Evidence).filter(Evidence.case_id == case.id).count()

    if total_evidence == 0:
        return AnalysisProgressSummaryResponse(
            case_id=case.case_id,
            total_evidence=0,
            analyzed_evidence=0,
            pending_analysis=0,
            partial_analysis=0,
            high_critical_evidence=0,
            overall_analysis_progress=0.0
        )

    analyzed_evidence = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id == case.id,
        EPRAResult.analysis_status == "COMPLETE"
    ).distinct().count()

    partial_analysis = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id == case.id,
        EPRAResult.analysis_status == "PARTIAL / PENDING INPUTS"
    ).distinct().count()

    pending_analysis = max(0, total_evidence - analyzed_evidence - partial_analysis)

    high_critical_evidence = db.query(EPRAResult.evidence_id).filter(
        EPRAResult.case_id == case.id,
        EPRAResult.priority.in_(["High", "Critical", "HIGH", "CRITICAL"])
    ).distinct().count()

    overall_analysis_progress = round((analyzed_evidence / total_evidence) * 100.0, 2)

    return AnalysisProgressSummaryResponse(
        case_id=case.case_id,
        total_evidence=total_evidence,
        analyzed_evidence=analyzed_evidence,
        pending_analysis=pending_analysis,
        partial_analysis=partial_analysis,
        high_critical_evidence=high_critical_evidence,
        overall_analysis_progress=overall_analysis_progress
    )


def get_investigator_analysis_evidence_repository(
    db: Session,
    case_identifier: str | int,
    current_user: User,
    search: Optional[str] = None,
    file_type: Optional[str] = None,
    analysis_status: Optional[str] = None,
    priority: Optional[str] = None,
    page: int = 1,
    limit: int = 10
) -> EvidenceAnalysisPage:
    """
    Returns paginated evidence analysis items for the assigned case with filters:
    - search
    - file_type
    - analysis_status (COMPLETE, PARTIAL / PENDING INPUTS, Pending)
    - priority (Critical, High, Medium, Low, Very Low)
    Unanalyzed evidence cleanly falls back to analysis_status = 'Pending' without DB insertion.
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)

    query = (
        db.query(Evidence, EPRAResult)
        .outerjoin(EPRAResult, Evidence.id == EPRAResult.evidence_id)
        .filter(Evidence.case_id == case.id)
    )

    if isinstance(search, str) and search.strip():
        s = f"%{search.strip()}%"
        query = query.filter(
            or_(
                Evidence.evidence_id.ilike(s),
                Evidence.file_name.ilike(s)
            )
        )

    if isinstance(file_type, str) and file_type.strip():
        query = query.filter(Evidence.file_type.ilike(file_type.strip()))

    if isinstance(analysis_status, str) and analysis_status.strip():
        ast = analysis_status.strip().upper()
        if ast == "PENDING":
            query = query.filter(
                or_(
                    EPRAResult.id == None,
                    EPRAResult.analysis_status != "COMPLETE"
                )
            )
        elif ast in ["COMPLETE", "COMPLETED"]:
            query = query.filter(EPRAResult.analysis_status == "COMPLETE")
        elif ast in ["PARTIAL", "PARTIAL / PENDING INPUTS"]:
            query = query.filter(EPRAResult.analysis_status == "PARTIAL / PENDING INPUTS")
        else:
            query = query.filter(EPRAResult.analysis_status.ilike(f"%{analysis_status.strip()}%"))

    if isinstance(priority, str) and priority.strip():
        query = query.filter(EPRAResult.priority.ilike(priority.strip()))

    total = query.count()
    offset = (page - 1) * limit
    results = (
        query
        .order_by(EPRAResult.rank.asc().nullslast(), Evidence.id.desc())
        .offset(offset)
        .limit(limit)
        .all()
    )

    items: List[EvidenceAnalysisItem] = []
    for ev, epra in results:
        if epra:
            status_val = epra.analysis_status or "COMPLETE"
            prio = epra.priority
            score = epra.epra_score
            rank = epra.rank
            pending_inputs = epra.pending_external_inputs or []
            processed_at = epra.processed_at
        else:
            status_val = "Pending"
            prio = None
            score = None
            rank = None
            pending_inputs = []
            processed_at = None

        items.append(
            EvidenceAnalysisItem(
                id=ev.id,
                evidence_id=ev.evidence_id,
                file_name=ev.file_name,
                file_type=ev.file_type,
                analysis_status=status_val,
                priority=prio,
                epra_score=score,
                rank=rank,
                pending_inputs=pending_inputs,
                processed_at=processed_at
            )
        )

    return EvidenceAnalysisPage(
        total=total,
        page=page,
        limit=limit,
        items=items
    )


def get_investigator_epra_priority_distribution(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> EPRAPriorityDistributionResponse:
    """
    Returns genuine priority breakdown across all analyzed evidence in the assigned case.
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)

    results = db.query(EPRAResult.priority).filter(
        EPRAResult.case_id == case.id
    ).all()

    crit = 0
    high = 0
    med = 0
    low = 0
    very_low = 0

    for (prio,) in results:
        if not prio:
            continue
        p = prio.strip().lower()
        if p == "critical":
            crit += 1
        elif p == "high":
            high += 1
        elif p == "medium":
            med += 1
        elif p == "low":
            low += 1
        elif p in ["very low", "very_low"]:
            very_low += 1

    total_analyzed = crit + high + med + low + very_low

    return EPRAPriorityDistributionResponse(
        case_id=case.case_id,
        critical=crit,
        high=high,
        medium=med,
        low=low,
        very_low=very_low,
        total_analyzed=total_analyzed
    )


def get_investigator_pending_analysis(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> PendingAnalysisResponse:
    """
    Returns evidence items awaiting complete analysis:
    - Not yet analyzed
    - OR status == 'PARTIAL / PENDING INPUTS'
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)

    rows = (
        db.query(Evidence, EPRAResult)
        .outerjoin(EPRAResult, Evidence.id == EPRAResult.evidence_id)
        .filter(
            Evidence.case_id == case.id,
            or_(
                EPRAResult.id == None,
                EPRAResult.analysis_status != "COMPLETE"
            )
        )
        .order_by(Evidence.id.asc())
        .all()
    )

    items: List[PendingAnalysisItem] = []
    for ev, epra in rows:
        if epra:
            st = epra.analysis_status or "PARTIAL / PENDING INPUTS"
            p_inputs = epra.pending_external_inputs or []
            dt = epra.processed_at or ev.created_at
        else:
            st = "Pending"
            p_inputs = []
            dt = ev.created_at

        items.append(
            PendingAnalysisItem(
                id=ev.id,
                evidence_id=ev.evidence_id,
                file_name=ev.file_name,
                file_type=ev.file_type,
                analysis_status=st,
                pending_inputs=p_inputs,
                last_updated=dt
            )
        )

    return PendingAnalysisResponse(
        case_id=case.case_id,
        total_pending=len(items),
        items=items
    )


def get_investigator_single_analysis_detail(
    db: Session,
    case_identifier: str | int,
    evidence_identifier: str | int,
    current_user: User
) -> InvestigatorAnalysisDetailResponse:
    """
    Returns single evidence EPRA analysis detail read-only:
    - If analyzed, returns genuine risk factors (AR, CI, BI, SI, II), IPI, score, priority, rank, pending_inputs.
    - If unanalyzed, returns clean 'Pending' fallback without fake DB row.
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

    epra = db.query(EPRAResult).filter(EPRAResult.evidence_id == evidence.id).first()

    if not epra:
        return InvestigatorAnalysisDetailResponse(
            evidence_id=evidence.evidence_id,
            file_name=evidence.file_name,
            evidence_type=evidence.file_type,
            file_size=evidence.file_size,
            analysis_status="Pending",
            semantic_status="PENDING",
            authenticity_risk=None,
            context_intelligence=None,
            behaviour_intelligence=None,
            semantic_intelligence=None,
            investigative_intelligence=None,
            ipi=None,
            epra_score=None,
            priority=None,
            rank=None,
            pending_inputs=[],
            hash_verified=False,
            duplicate=False,
            processed_at=None
        )

    return InvestigatorAnalysisDetailResponse(
        evidence_id=evidence.evidence_id,
        file_name=evidence.file_name,
        evidence_type=evidence.file_type,
        file_size=evidence.file_size,
        analysis_status=epra.analysis_status or "COMPLETE",
        semantic_status=epra.semantic_status,
        authenticity_risk=epra.authenticity_risk,
        context_intelligence=epra.context_intelligence,
        behaviour_intelligence=epra.behaviour_intelligence,
        semantic_intelligence=epra.semantic_intelligence,
        investigative_intelligence=epra.investigative_intelligence,
        ipi=epra.ipi,
        epra_score=epra.epra_score,
        priority=epra.priority,
        rank=epra.rank,
        pending_inputs=epra.pending_external_inputs or [],
        hash_verified=epra.hash_verified or False,
        duplicate=epra.is_duplicate or False,
        processed_at=epra.processed_at
    )


# ==============================================================================
# 12. INVESTIGATOR VIEW CASE: RELATIONSHIP VIEW TAB
# ==============================================================================

def get_investigator_relationship_view(
    db: Session,
    case_identifier: str | int,
    current_user: User,
    node_type: Optional[str] = None,
    relationship_type: Optional[str] = None,
    priority: Optional[str] = None
) -> GraphResponse:
    """
    Returns complete case relationship graph for assigned investigator with optional filtering:
    - Node types: Evidence, Possible Entity, Device, Case
    - Edges: Evidence-Suspect, Evidence-Device, Verified Duplicate (SHA-256), CBIR Visual Similarity
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)
    return RelationshipGraphService.get_relationship_graph(
        db=db,
        case_id=str(case.case_id),
        current_user=current_user,
        node_type=node_type,
        relationship_type=relationship_type,
        priority=priority
    )


def get_investigator_relationship_node_detail(
    db: Session,
    case_identifier: str | int,
    node_id: str,
    current_user: User
) -> RelationshipNodeDetailResponse:
    """
    Returns deep, genuine details for a selected relationship graph node:
    - Evidence node: file attributes, verified hash, genuine EPRA rank, score, priority, status, connected edges
    - Possible Entity: confidence, rank, total EPRA score, linked evidence (labeled Possible Entity, not confirmed)
    - Device node: linked evidence items and notes
    - Case node: genuine case details
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)
    try:
        detail = RelationshipGraphService.get_node_detail(
            db=db,
            case_id=str(case.case_id),
            node_id=node_id,
            current_user=current_user
        )
    except FileNotFoundError as e:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(e)
        )
    return RelationshipNodeDetailResponse(
        node_id=detail["node_id"],
        node_type=detail["node_type"],
        label=detail["label"],
        properties=detail["properties"],
        connected_nodes_count=detail["connected_nodes_count"],
        connected_edges=detail["connected_edges"]
    )


# ==============================================================================
# 10. INVESTIGATOR VIEW CASE: CASE ACTIVITY TAB
# ==============================================================================

def _collect_normalized_case_activities(
    db: Session,
    case: Case
) -> List[InvestigatorCaseActivityItem]:
    """
    Collects and normalizes all authentic activity events for a case across
    CustodyLog, ActivityLog, CaseTimeline, ReportRecord, EPRAResult, CBIRResult,
    EvidenceLink, and Evidence records.
    Deduplicates using event_reference and composite keys so no real action is duplicated.
    Sorts descending (newest first).
    """
    clean_case_ids = list({str(case.id), str(case.case_id)}) if case.case_id else [str(case.id)]
    num_case_id = case.id

    all_items: List[InvestigatorCaseActivityItem] = []
    seen_event_refs: set = set()
    seen_evidence_uploads: set = set()
    seen_case_creations = False
    seen_reports: set = set()

    # User cache for resolving actor names
    user_cache: Dict[int, str] = {}
    def _resolve_user_name(user_id: Optional[int]) -> Optional[str]:
        if not user_id:
            return None
        if user_id not in user_cache:
            u = db.query(User).filter(User.id == user_id).first()
            user_cache[user_id] = u.full_name if u else None
        return user_cache[user_id]

    # 1. Custody Logs & Activity Logs (Deduplicated via TimelineService-style logic)
    custody_entries = db.query(CustodyLog).filter(
        CustodyLog.case_id.in_(clean_case_ids)
    ).all()

    activity_entries = db.query(ActivityLog).filter(
        ActivityLog.case_id.in_(clean_case_ids)
    ).all()

    grouped_logs: Dict[str, Dict[str, Any]] = {}

    for c in custody_entries:
        ref = c.event_reference or f"CUST_{c.id}"
        dt = c.timestamp
        if ref not in grouped_logs:
            grouped_logs[ref] = {
                "dt": dt,
                "event_ref": c.event_reference,
                "evidence_id": c.evidence_id,
                "action": c.action or c.event_type or "CUSTODY_EVENT",
                "title": c.title or f"Custody Event: {c.action}",
                "actor": c.investigator_name,
                "actor_role": c.actor_role,
                "actor_id": c.investigator_id,
                "result": c.result or "SUCCESS",
                "remarks": [c.remarks] if c.remarks else [],
                "source": "CHAIN_OF_CUSTODY",
                "custody_id": c.id,
                "activity_id_val": f"act_cust_{c.id}"
            }
        else:
            if c.remarks and c.remarks not in grouped_logs[ref]["remarks"]:
                grouped_logs[ref]["remarks"].append(c.remarks)

    for a in activity_entries:
        ref = a.event_reference or f"ACT_{a.id}"
        dt = a.timestamp
        ev_id = a.external_evidence_id or (str(a.evidence_id) if a.evidence_id is not None else None)
        if ref not in grouped_logs:
            grouped_logs[ref] = {
                "dt": dt,
                "event_ref": a.event_reference,
                "evidence_id": ev_id,
                "action": a.action or a.activity or "ACTIVITY_EVENT",
                "title": a.activity or f"Activity: {a.action}",
                "actor": a.investigator_name,
                "actor_role": None,
                "actor_id": a.actor_id,
                "result": a.outcome or "SUCCESS",
                "remarks": [a.details] if a.details else [],
                "source": "ACTIVITY_LOG",
                "act_id": a.id,
                "activity_id_val": f"act_act_{a.id}"
            }
        else:
            if a.details and a.details not in grouped_logs[ref]["remarks"]:
                grouped_logs[ref]["remarks"].append(a.details)
            if not grouped_logs[ref].get("evidence_id") and ev_id:
                grouped_logs[ref]["evidence_id"] = ev_id

    for ref, g in grouped_logs.items():
        dt = g["dt"] or case.created_at
        act = (g["action"] or "").upper()
        ev_id = g.get("evidence_id")
        remarks_str = " | ".join(g["remarks"])

        # Categorize
        if "UPLOAD" in act or "ACQUISITION" in act:
            act_type = "EVIDENCE"
            if ev_id:
                seen_evidence_uploads.add(str(ev_id))
        elif "HASH" in act or "INTEGRITY" in act:
            act_type = "INTEGRITY"
        elif "REPORT" in act:
            act_type = "REPORT"
        elif "METADATA" in act:
            act_type = "METADATA"
        elif any(k in act for k in ["TRANSFER", "ACCESS", "CUSTODY", "UPDATE"]):
            act_type = "CUSTODY"
        else:
            act_type = "CUSTODY"

        title = g["title"]
        desc = f"{title}. {remarks_str}".strip() if remarks_str else title

        actor_uid = int(g["actor_id"]) if g.get("actor_id") and str(g["actor_id"]).isdigit() else None

        all_items.append(
            InvestigatorCaseActivityItem(
                activity_id=g["activity_id_val"],
                case_id=str(case.case_id or case.id),
                activity_type=act_type,
                action=g["action"],
                title=title,
                description=desc,
                source_module=g["source"],
                evidence_id=str(ev_id) if ev_id else None,
                report_id=None,
                actor_user_id=actor_uid,
                actor_name=g["actor"],
                actor_role=g["actor_role"],
                timestamp=dt,
                timestamp_formatted=dt.strftime("%d %b %Y, %H:%M") if dt else None,
                status=g["result"],
                additional_details={"remarks": remarks_str} if remarks_str else None
            )
        )
        if g.get("event_ref"):
            seen_event_refs.add(g["event_ref"])

    # 2. CaseTimeline entries
    ct_entries = db.query(CaseTimeline).filter(
        CaseTimeline.case_id == num_case_id
    ).all()

    for ct in ct_entries:
        ev_lower = (ct.event or "").lower()
        if "case created" in ev_lower or "initialized" in ev_lower:
            seen_case_creations = True

        # If it is an evidence upload entry, check if already recorded
        if "evidence uploaded" in ev_lower:
            # Extract evidence id if possible
            matched_upload = False
            for ev_u in seen_evidence_uploads:
                if ev_u.lower() in ev_lower:
                    matched_upload = True
                    break
            if matched_upload:
                continue

        # Categorize
        if "evidence" in ev_lower:
            act_type = "EVIDENCE"
            action_code = "EVIDENCE_EVENT"
        elif "report" in ev_lower:
            act_type = "REPORT"
            action_code = "REPORT_EVENT"
        elif "custody" in ev_lower:
            act_type = "CUSTODY"
            action_code = "CUSTODY_EVENT"
        elif "expert" in ev_lower or "investigator" in ev_lower or "assigned" in ev_lower:
            act_type = "CASE"
            action_code = "CASE_ASSIGNMENT"
        elif "status" in ev_lower:
            act_type = "CASE"
            action_code = "CASE_STATUS_UPDATE"
        else:
            act_type = "CASE"
            action_code = "CASE_MILESTONE"

        actor_name = _resolve_user_name(ct.performed_by)
        dt = ct.created_at or case.created_at

        all_items.append(
            InvestigatorCaseActivityItem(
                activity_id=f"act_ct_{ct.id}",
                case_id=str(case.case_id or case.id),
                activity_type=act_type,
                action=action_code,
                title=ct.event,
                description=ct.event,
                source_module="CASE_MANAGEMENT",
                evidence_id=None,
                report_id=None,
                actor_user_id=ct.performed_by,
                actor_name=actor_name,
                actor_role=ct.performed_by_role,
                timestamp=dt,
                timestamp_formatted=dt.strftime("%d %b %Y, %H:%M") if dt else None,
                status="SUCCESS",
                additional_details=None
            )
        )

    # 3. Report Records
    rep_records = db.query(ReportRecord).filter(
        ReportRecord.case_id.in_(clean_case_ids),
        ReportRecord.is_draft == False
    ).all()

    for r in rep_records:
        seen_reports.add(r.id)
        # Check if already covered by an existing activity with event_ref == r.event_reference
        already_covered = False
        if r.event_reference and r.event_reference in seen_event_refs:
            already_covered = True

        if not already_covered:
            dt = r.generated_at or case.created_at
            all_items.append(
                InvestigatorCaseActivityItem(
                    activity_id=f"act_rep_{r.id}",
                    case_id=str(case.case_id or case.id),
                    activity_type="REPORT",
                    action="REPORT_GENERATED",
                    title=f"Technical Report Generated: {r.report_type}",
                    description=f"Official {r.report_type} generated in {r.file_format} format ({r.file_name}) by {r.investigator_name}.",
                    source_module="TECHNICAL_REPORTS",
                    evidence_id=None,
                    report_id=r.id,
                    actor_user_id=int(r.generated_by_id) if r.generated_by_id and r.generated_by_id.isdigit() else None,
                    actor_name=r.investigator_name,
                    actor_role=r.generated_by_role,
                    timestamp=dt,
                    timestamp_formatted=dt.strftime("%d %b %Y, %H:%M") if dt else None,
                    status="FINALIZED",
                    additional_details={
                        "report_id": r.id,
                        "file_name": r.file_name,
                        "file_format": r.file_format,
                        "file_size_bytes": r.file_size_bytes
                    }
                )
            )

    # 4. EPRA Results (Grouped by analysis run timestamp)
    epra_runs = db.query(
        EPRAResult.created_at,
        func.count(EPRAResult.id).label("count")
    ).filter(
        EPRAResult.case_id == num_case_id
    ).group_by(EPRAResult.created_at).all()

    for run_ts, count in epra_runs:
        if run_ts:
            all_items.append(
                InvestigatorCaseActivityItem(
                    activity_id=f"act_epra_{run_ts.strftime('%Y%m%d%H%M%S')}",
                    case_id=str(case.case_id or case.id),
                    activity_type="EPRA",
                    action="EPRA_ANALYSIS_COMPLETED",
                    title="EPRA Risk Prioritization Completed",
                    description=f"Automated forensic risk prioritization analysis completed for {count} evidence item(s).",
                    source_module="EPRA_AI_ENGINE",
                    evidence_id=None,
                    report_id=None,
                    actor_user_id=case.cyber_expert_id,
                    actor_name=_resolve_user_name(case.cyber_expert_id),
                    actor_role="Cyber Expert",
                    timestamp=run_ts,
                    timestamp_formatted=run_ts.strftime("%d %b %Y, %H:%M"),
                    status="COMPLETE",
                    additional_details={"analyzed_items_count": count}
                )
            )

    # 5. CBIR Results (Grouped by query evidence and run timestamp)
    cbir_runs = db.query(
        CBIRResult.query_evidence_id,
        CBIRResult.created_at,
        func.count(CBIRResult.id).label("count")
    ).filter(
        CBIRResult.case_id == num_case_id
    ).group_by(CBIRResult.query_evidence_id, CBIRResult.created_at).all()

    for q_ev_id, run_ts, count in cbir_runs:
        if run_ts:
            all_items.append(
                InvestigatorCaseActivityItem(
                    activity_id=f"act_cbir_{q_ev_id}_{run_ts.strftime('%Y%m%d%H%M%S')}",
                    case_id=str(case.case_id or case.id),
                    activity_type="CBIR",
                    action="CBIR_COMPARISON_EXECUTED",
                    title="CBIR Visual Similarity Comparison",
                    description=f"Multi-signal visual similarity comparison executed for Query Evidence #{q_ev_id} ({count} candidates evaluated).",
                    source_module="CBIR_VISION_ENGINE",
                    evidence_id=str(q_ev_id),
                    report_id=None,
                    actor_user_id=case.cyber_expert_id,
                    actor_name=_resolve_user_name(case.cyber_expert_id),
                    actor_role="Cyber Expert",
                    timestamp=run_ts,
                    timestamp_formatted=run_ts.strftime("%d %b %Y, %H:%M"),
                    status="COMPLETED",
                    additional_details={"candidates_count": count}
                )
            )

    # 6. EvidenceLink entries
    link_entries = db.query(EvidenceLink).filter(
        EvidenceLink.case_id == num_case_id
    ).all()

    for l in link_entries:
        target_desc = f"Target Suspect: {l.suspect_name}" if l.suspect_name else (f"Target Device: {l.device_name}" if l.device_name else "")
        desc = f"Forensic relational link established ({l.relationship_type}) for Evidence #{l.evidence_id}. {target_desc}".strip()
        dt = l.created_at or case.created_at
        all_items.append(
            InvestigatorCaseActivityItem(
                activity_id=f"act_link_{l.id}",
                case_id=str(case.case_id or case.id),
                activity_type="RELATIONSHIP",
                action="RELATIONSHIP_LINK_ESTABLISHED",
                title=f"Relationship Link: {l.relationship_type}",
                description=desc,
                source_module="RELATIONSHIP_GRAPH",
                evidence_id=str(l.evidence_id),
                report_id=None,
                actor_user_id=None,
                actor_name=None,
                actor_role=None,
                timestamp=dt,
                timestamp_formatted=dt.strftime("%d %b %Y, %H:%M") if dt else None,
                status="ACTIVE",
                additional_details={"link_id": l.id, "relationship_type": l.relationship_type, "notes": l.notes}
            )
        )

    # 7. Untracked Evidence Uploads (fallback if not in CustodyLog/CaseTimeline)
    evidences = db.query(Evidence).filter(
        Evidence.case_id == num_case_id
    ).all()

    for ev in evidences:
        ev_id_str = str(ev.evidence_id or ev.id)
        if ev_id_str not in seen_evidence_uploads and str(ev.id) not in seen_evidence_uploads:
            dt = ev.created_at or case.created_at
            all_items.append(
                InvestigatorCaseActivityItem(
                    activity_id=f"act_ev_upload_{ev.id}",
                    case_id=str(case.case_id or case.id),
                    activity_type="EVIDENCE",
                    action="EVIDENCE_UPLOADED",
                    title=f"Evidence Uploaded: {ev.evidence_id}",
                    description=f"Evidence file '{ev.file_name}' ({ev.file_type or 'Unknown'}) registered in evidence repository.",
                    source_module="EVIDENCE_MANAGEMENT",
                    evidence_id=ev_id_str,
                    report_id=None,
                    actor_user_id=case.investigator_id,
                    actor_name=_resolve_user_name(case.investigator_id),
                    actor_role="Investigator",
                    timestamp=dt,
                    timestamp_formatted=dt.strftime("%d %b %Y, %H:%M") if dt else None,
                    status="ACTIVE",
                    additional_details={"file_name": ev.file_name, "file_size": ev.file_size}
                )
            )

    # 8. Baseline Case Initialization (if no CaseTimeline creation entry)
    if not seen_case_creations and case.created_at:
        all_items.append(
            InvestigatorCaseActivityItem(
                activity_id=f"act_case_init_{case.id}",
                case_id=str(case.case_id or case.id),
                activity_type="CASE",
                action="CASE_CREATED",
                title=f"Case Initialized: {case.title}",
                description=f"Investigation case {case.case_id} ({case.title}) created.",
                source_module="CASE_MANAGEMENT",
                evidence_id=None,
                report_id=None,
                actor_user_id=case.investigator_id,
                actor_name=_resolve_user_name(case.investigator_id),
                actor_role="Investigator",
                timestamp=case.created_at,
                timestamp_formatted=case.created_at.strftime("%d %b %Y, %H:%M"),
                status="INITIALIZED",
                additional_details={"priority": case.priority, "status": case.status}
            )
        )

    # Sort descending by timestamp (deterministic secondary sort by activity_id)
    all_items.sort(key=lambda x: (-(x.timestamp.timestamp() if x.timestamp else 0), x.activity_id))
    return all_items


def get_investigator_case_activity_summary(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> InvestigatorCaseActivitySummaryResponse:
    """
    Returns summary activity metrics for the selected case assigned to current investigator.
    Counts activities by category derived dynamically from authentic records.
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)
    activities = _collect_normalized_case_activities(db, case)

    counts = {
        "EVIDENCE": 0,
        "EPRA": 0,
        "CBIR": 0,
        "INTEGRITY": 0,
        "CUSTODY": 0,
        "RELATIONSHIP": 0,
        "REPORT": 0,
        "CASE": 0
    }

    for a in activities:
        t = a.activity_type.upper()
        if t in counts:
            counts[t] += 1
        elif t == "METADATA":
            counts["EVIDENCE"] += 1
        else:
            counts["CASE"] += 1

    latest_dt = activities[0].timestamp if activities else None

    return InvestigatorCaseActivitySummaryResponse(
        case_id=str(case.case_id or case.id),
        total_activity_count=len(activities),
        evidence_activity_count=counts["EVIDENCE"],
        analysis_activity_count=counts["EPRA"] + counts["CBIR"],
        integrity_activity_count=counts["INTEGRITY"],
        custody_activity_count=counts["CUSTODY"],
        relationship_activity_count=counts["RELATIONSHIP"],
        report_activity_count=counts["REPORT"],
        case_activity_count=counts["CASE"],
        latest_activity_at=latest_dt,
        latest_activity_formatted=latest_dt.strftime("%d %b %Y, %H:%M") if latest_dt else None
    )


def get_investigator_case_activity_timeline(
    db: Session,
    case_identifier: str | int,
    current_user: User,
    activity_type: Optional[str] = None,
    source_module: Optional[str] = None,
    start_date: Optional[datetime] = None,
    end_date: Optional[datetime] = None,
    search: Optional[str] = None,
    page: int = 1,
    limit: int = 10
) -> InvestigatorCaseActivityPage:
    """
    Returns paginated, searchable, filterable forensic activity timeline for the assigned case.
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)
    activities = _collect_normalized_case_activities(db, case)

    filtered = activities

    # 1. Filter by activity_type
    if activity_type and activity_type.upper() != "ALL":
        target_type = activity_type.upper().strip()
        filtered = [a for a in filtered if a.activity_type.upper() == target_type]

    # 2. Filter by source_module
    if source_module and source_module.upper() != "ALL":
        target_mod = source_module.upper().strip()
        filtered = [a for a in filtered if target_mod in (a.source_module or "").upper()]

    # 3. Filter by date range
    if start_date:
        filtered = [a for a in filtered if a.timestamp and a.timestamp >= start_date]
    if end_date:
        filtered = [a for a in filtered if a.timestamp and a.timestamp <= end_date]

    # 4. Text Search
    if search and search.strip():
        q = search.strip().lower()
        filtered = [
            a for a in filtered
            if q in (a.title or "").lower()
            or q in (a.description or "").lower()
            or q in (a.action or "").lower()
            or q in (a.actor_name or "").lower()
            or q in (a.evidence_id or "").lower()
            or q in (a.report_id or "").lower()
        ]

    total = len(filtered)
    total_pages = (total + limit - 1) // limit if limit > 0 else 1
    offset = (max(1, page) - 1) * limit
    page_items = filtered[offset:offset + limit]

    return InvestigatorCaseActivityPage(
        case_id=str(case.case_id or case.id),
        total=total,
        page=page,
        limit=limit,
        total_pages=total_pages,
        activities=page_items
    )


def get_investigator_case_activity_detail(
    db: Session,
    case_identifier: str | int,
    activity_id: str,
    current_user: User
) -> InvestigatorActivityDetailResponse:
    """
    Resolves rich contextual forensic detail for an activity timeline event.
    Pulls related Evidence, Integrity, Metadata, EPRA, Custody, or Report records without fabricating.
    """
    case = get_investigator_assigned_case(db, case_identifier, current_user)
    activities = _collect_normalized_case_activities(db, case)

    clean_act_id = str(activity_id).strip()
    target_act = next((a for a in activities if a.activity_id == clean_act_id), None)

    if not target_act:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Activity record '{activity_id}' not found for this case."
        )

    evidence_details = None
    integrity_details = None
    metadata_details = None
    epra_details = None
    custody_details = None
    report_details = None
    relationship_details = None

    # 1. Resolve Evidence context
    if target_act.evidence_id:
        ev = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            or_(
                Evidence.evidence_id == target_act.evidence_id,
                Evidence.id == (int(target_act.evidence_id) if target_act.evidence_id.isdigit() else -1)
            )
        ).first()

        if ev:
            evidence_details = {
                "id": ev.id,
                "evidence_id": ev.evidence_id,
                "file_name": ev.file_name,
                "file_type": ev.file_type,
                "file_size": ev.file_size,
                "status": ev.status,
                "created_at": ev.created_at.isoformat() if ev.created_at else None
            }

            # Integrity
            eh = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
            if eh:
                integrity_details = {
                    "current_hash": eh.current_hash or eh.sha256_hash,
                    "original_hash": eh.original_hash,
                    "hash_match": eh.hash_match,
                    "tampered": eh.tampered,
                    "integrity_status": eh.integrity_status,
                    "verified_at": eh.verified_at.isoformat() if eh.verified_at else None
                }

            # Metadata
            er = db.query(EvidenceRecord).filter(
                (EvidenceRecord.external_evidence_id == ev.evidence_id) |
                (EvidenceRecord.id == ev.id)
            ).first()
            if er:
                metadata_details = {
                    "mime_type": er.detected_mime_type or er.file_type,
                    "file_size_formatted": er.file_size_formatted,
                    "image_width": er.image_width,
                    "image_height": er.image_height,
                    "verification_status": er.verification_status
                }

            # EPRA
            ep = db.query(EPRAResult).filter(
                EPRAResult.case_id == case.id,
                EPRAResult.evidence_id == ev.id
            ).first()
            if ep:
                epra_details = {
                    "epra_score": ep.epra_score,
                    "priority": ep.priority,
                    "rank": ep.rank,
                    "analysis_status": ep.analysis_status,
                    "authenticity_risk": ep.authenticity_risk,
                    "context_intelligence": ep.context_intelligence,
                    "behaviour_intelligence": ep.behaviour_intelligence,
                    "semantic_intelligence": ep.semantic_intelligence
                }

            # Custody
            ci = db.query(CurrentCustodyInfo).filter(
                CurrentCustodyInfo.evidence_id == (ev.evidence_id or str(ev.id))
            ).first()
            if ci:
                custody_details = {
                    "current_holder_name": ci.current_holder_name,
                    "current_holder_role": ci.current_holder_role,
                    "department": ci.department,
                    "location": ci.location,
                    "assigned_on": ci.assigned_on.isoformat() if ci.assigned_on else None,
                    "last_accessed": ci.last_accessed.isoformat() if ci.last_accessed else None,
                    "custody_status": ci.custody_status
                }

    # 2. Resolve Report context
    if target_act.report_id or target_act.activity_type == "REPORT":
        rep_id = target_act.report_id
        if not rep_id and clean_act_id.startswith("act_rep_"):
            rep_id = clean_act_id[len("act_rep_"):]

        if rep_id:
            rep = db.query(ReportRecord).filter(ReportRecord.id == rep_id).first()
            if rep:
                report_details = {
                    "report_id": rep.id,
                    "report_name": rep.file_name,
                    "report_type": rep.report_type,
                    "file_format": rep.file_format,
                    "file_size_bytes": rep.file_size_bytes,
                    "generated_at": rep.generated_at.isoformat() if rep.generated_at else None,
                    "investigator_name": rep.investigator_name,
                    "generated_by_role": rep.generated_by_role,
                    "download_url": f"/cases/{case.case_id or case.id}/reports/download/{rep.id}",
                    "preview_url": f"/cases/{case.case_id or case.id}/reports/preview/{rep.id}"
                }

    # 3. Resolve Relationship context
    if target_act.activity_type == "RELATIONSHIP" and clean_act_id.startswith("act_link_"):
        link_id_str = clean_act_id[len("act_link_"):]
        if link_id_str.isdigit():
            link = db.query(EvidenceLink).filter(EvidenceLink.id == int(link_id_str)).first()
            if link:
                relationship_details = {
                    "link_id": link.id,
                    "evidence_id": link.evidence_id,
                    "suspect_name": link.suspect_name,
                    "device_name": link.device_name,
                    "relationship_type": link.relationship_type,
                    "notes": link.notes
                }

    return InvestigatorActivityDetailResponse(
        activity_id=target_act.activity_id,
        case_id=target_act.case_id,
        activity_type=target_act.activity_type,
        action=target_act.action,
        title=target_act.title,
        description=target_act.description,
        source_module=target_act.source_module,
        timestamp=target_act.timestamp,
        timestamp_formatted=target_act.timestamp_formatted,
        actor_name=target_act.actor_name,
        actor_role=target_act.actor_role,
        evidence_id=target_act.evidence_id,
        report_id=target_act.report_id,
        status=target_act.status,
        evidence_details=evidence_details,
        integrity_details=integrity_details,
        metadata_details=metadata_details,
        epra_details=epra_details,
        custody_details=custody_details,
        report_details=report_details,
        relationship_details=relationship_details,
        raw_details=target_act.additional_details
    )



