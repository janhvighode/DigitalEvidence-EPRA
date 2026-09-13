from typing import Optional, List, Dict, Any
from datetime import datetime
from sqlalchemy.orm import Session, aliased
from sqlalchemy import or_, func

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from models.notification import Notification

from schemas.investigator_dashboard import (
    InvestigatorDashboardStats,
    CaseRequiringAttentionItem,
    InvestigatorEvidenceStatusResponse,
    CaseStatusDistributionResponse,
    InvestigatorCaseItem,
    InvestigatorMyCasesPage
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
