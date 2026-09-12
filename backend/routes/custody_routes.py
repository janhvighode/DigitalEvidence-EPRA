from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from models.case import Case
from models.evidence import Evidence
from utils.current_user import get_current_user
from services.custody_service import CustodyService
from services.custody_adapter import CustodyAdapter
from schemas.custody import (
    TransferInitiateRequest,
    TransferReceiveRequest,
    CurrentCustodyUpdateRequest,
    CustodySummaryResponse,
    CustodyTimelineResponse,
    CurrentCustodyResponse,
    TransferHistoryResponse
)

router = APIRouter(
    prefix="/cases/{case_id}/chain-of-custody",
    tags=["Chain of Custody"]
)


def verify_cyber_expert_case_access(case_id: int, current_user: User, db: Session) -> Case:
    """
    Enforce Cyber Expert authorization and assigned case boundary.
    - Missing/invalid JWT -> 401 (handled by get_current_user)
    - Role != Cyber Expert (role_id != 3) -> 403 Forbidden
    - Case not found -> 404 Not Found
    - Case not assigned to current Cyber Expert -> 403 Forbidden
    """
    if not current_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )
    if current_user.role_id != 3:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to Cyber Experts only"
        )

    case = db.query(Case).filter(Case.id == case_id).first()
    if not case:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Case #{case_id} not found"
        )

    if case.cyber_expert_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"You are not assigned to Case #{case_id}"
        )

    return case


def verify_evidence_in_case(case_id: int, evidence_id: str, db: Session) -> Evidence:
    """
    Verify evidence exists and strictly belongs to the specified case.
    Rejects foreign evidence with 404 to avoid cross-case leakage.
    """
    clean_id = str(evidence_id).strip()
    ev = db.query(Evidence).filter(
        (Evidence.evidence_id == clean_id) |
        (Evidence.id == int(clean_id) if clean_id.isdigit() else False)
    ).first()

    if not ev:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Evidence '{evidence_id}' not found"
        )

    if ev.case_id != case_id:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Evidence '{evidence_id}' does not belong to Case #{case_id}"
        )

    return ev


# ==============================================================================
# 1. SUMMARY CARDS
# ==============================================================================

@router.get("/summary", response_model=CustodySummaryResponse)
def get_custody_summary(
    case_id: int,
    evidence_id: Optional[str] = Query(None, description="Optional evidence ID to scope summary"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Dynamic summary metrics for the case or specific evidence item:
    - Total Events
    - Handlers (distinct human handlers)
    - Transfers (completed)
    - Pending Transfers
    - First Handled timestamp
    - Current Status
    No hardcoded values.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)

    # Sync authentic evidence upload and hash generation events idempotently
    CustodyAdapter.sync_authentic_evidence_events(db, case_id, current_user)

    if evidence_id:
        ev = verify_evidence_in_case(case_id, evidence_id, db)
        clean_ev_id = ev.evidence_id or str(ev.id)
        summary = CustodyService.get_custody_summary(db, clean_ev_id)
        summary["case_id"] = str(case_id)
        return summary

    summary = CustodyService.get_case_custody_summary(db, str(case_id))
    return summary


# ==============================================================================
# 2. CUSTODY TIMELINE / EVENTS
# ==============================================================================

@router.get("/timeline", response_model=CustodyTimelineResponse)
@router.get("/events", response_model=CustodyTimelineResponse)
def get_custody_timeline(
    case_id: int,
    evidence_id: Optional[str] = Query(None, description="Optional evidence ID filter"),
    event_filter: Optional[str] = Query("ALL", description="Filter by event type: ALL, TRANSFERS, ACCESS, ANALYSIS, REPORT, ACQUISITION, UPLOAD, HASH"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Chronological custody timeline for the case or evidence item.
    Supports event type filtering and deterministic ordering.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    CustodyAdapter.sync_authentic_evidence_events(db, case_id, current_user)

    clean_ev_id = None
    if evidence_id:
        ev = verify_evidence_in_case(case_id, evidence_id, db)
        clean_ev_id = ev.evidence_id or str(ev.id)

    events = CustodyService.get_custody_timeline(
        db=db,
        evidence_id=clean_ev_id,
        case_id=str(case_id),
        event_filter=event_filter
    )

    return {
        "case_id": str(case_id),
        "evidence_id": clean_ev_id,
        "filter_applied": event_filter or "ALL",
        "total_events": len(events),
        "events": events
    }


# ==============================================================================
# 3. CURRENT CUSTODY INFORMATION
# ==============================================================================

@router.get("/current", response_model=CurrentCustodyResponse)
def get_current_custody(
    case_id: int,
    evidence_id: str = Query(..., description="Evidence ID to inspect current custody"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Current Custody Information card for an evidence item.
    Returns actual holder, department, assigned on, last accessed, location, remarks, and status.
    Returns null for unset fields; never fabricates values.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, evidence_id, db)
    clean_ev_id = ev.evidence_id or str(ev.id)

    CustodyAdapter.sync_authentic_evidence_events(db, case_id, current_user)
    return CustodyService.get_current_custody(db, clean_ev_id, str(case_id))


@router.put("/current", response_model=CurrentCustodyResponse)
def update_current_custody(
    case_id: int,
    payload: CurrentCustodyUpdateRequest,
    evidence_id: str = Query(..., description="Evidence ID to update custody info"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Audited update of non-holder current custody details (location, department, remarks).
    Holder changes cannot be performed via direct edit; must follow transfer workflow.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, evidence_id, db)
    clean_ev_id = ev.evidence_id or str(ev.id)

    actor_name = current_user.full_name or current_user.username
    actor_id = str(current_user.id)
    actor_role = "Cyber Expert" if (current_user and current_user.role_id == 3) else ("Investigator" if (current_user and current_user.role_id == 2) else "Administrator")

    try:
        updated = CustodyService.update_current_custody(
            db=db,
            evidence_id=clean_ev_id,
            department=payload.department,
            location=payload.location,
            remarks=payload.remarks,
            actor_name=actor_name,
            actor_id=actor_id,
            actor_role=actor_role
        )
        return updated
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


# ==============================================================================
# 4. TRANSFER WORKFLOW (TWO-PHASE HANDSHAKE)
# ==============================================================================

@router.get("/transfers", response_model=TransferHistoryResponse)
def get_transfer_history(
    case_id: int,
    evidence_id: Optional[str] = Query(None, description="Optional evidence ID to filter transfers"),
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Paginated transfer history table.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)

    clean_ev_id = None
    if evidence_id:
        ev = verify_evidence_in_case(case_id, evidence_id, db)
        clean_ev_id = ev.evidence_id or str(ev.id)

    return CustodyService.get_transfer_history(
        db=db,
        evidence_id=clean_ev_id,
        case_id=str(case_id),
        page=page,
        page_size=page_size
    )


@router.post("/transfer/initiate")
def initiate_transfer(
    case_id: int,
    payload: TransferInitiateRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Initiate custody transfer. Generates unique transfer reference token.
    Enforces that evidence is marked PENDING_RECEIPT and cannot have contradictory transfers.
    Current holder does NOT change upon initiation.
    Sender identity derived strictly from JWT.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, payload.evidence_id, db)
    clean_ev_id = ev.evidence_id or str(ev.id)

    sender_name = current_user.full_name or current_user.username
    sender_id = str(current_user.id)
    sender_role = "Cyber Expert" if (current_user and current_user.role_id == 3) else ("Investigator" if (current_user and current_user.role_id == 2) else "Administrator")

    try:
        res = CustodyService.initiate_transfer(
            db=db,
            evidence_id=clean_ev_id,
            sender_name=sender_name,
            recipient_name=payload.recipient_name,
            remarks=payload.reason_or_remarks,
            sender_id=sender_id,
            recipient_id=payload.recipient_id,
            sender_role=sender_role,
            recipient_role=payload.recipient_role,
            case_id=str(case_id)
        )
        return res
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


@router.post("/transfer/receive")
def receive_transfer(
    case_id: int,
    payload: TransferReceiveRequest,
    transfer_reference: str = Query(..., description="Unique transfer reference token"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Confirm receipt of an in-flight transfer.
    Validates recipient and prevents duplicate receipt.
    Updates current holder officially upon confirmed receipt.
    Does NOT recalculate local file hashes.
    Recipient identity derived strictly from JWT.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)

    recipient_name = current_user.full_name or current_user.username
    recipient_id = str(current_user.id)
    recipient_role = "Cyber Expert" if (current_user and current_user.role_id == 3) else ("Investigator" if (current_user and current_user.role_id == 2) else "Administrator")

    # If payload provided recipient_name, check for matching
    if payload.recipient_name and payload.recipient_name.strip().lower() != recipient_name.strip().lower():
        recipient_name = payload.recipient_name.strip()

    try:
        res = CustodyService.receive_transfer(
            db=db,
            transfer_reference=transfer_reference,
            recipient_name=recipient_name,
            recipient_id=recipient_id,
            recipient_role=payload.recipient_role or recipient_role,
            department=payload.department,
            location=payload.location,
            remarks=payload.remarks
        )
        return res
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))


# ==============================================================================
# 5. ACCESS LOGGING
# ==============================================================================

@router.post("/access")
def record_evidence_access(
    case_id: int,
    evidence_id: str = Query(..., description="Evidence ID accessed for analysis"),
    purpose: str = Query("Forensic analysis inspection", description="Reason for accessing evidence"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Record that evidence was accessed for analysis.
    Updates last_accessed timestamp and custody status to 'In Analysis'.
    Does NOT assign or alter current holder.
    Actor derived strictly from JWT.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, evidence_id, db)
    clean_ev_id = ev.evidence_id or str(ev.id)

    actor_name = current_user.full_name or current_user.username
    actor_id = str(current_user.id)
    actor_role = "Cyber Expert" if (current_user and current_user.role_id == 3) else ("Investigator" if (current_user and current_user.role_id == 2) else "Administrator")

    return CustodyService.record_access_event(
        db=db,
        evidence_id=clean_ev_id,
        actor_name=actor_name,
        actor_id=actor_id,
        actor_role=actor_role,
        purpose=purpose,
        case_id=str(case_id)
    )


# ==============================================================================
# 6. UNIFIED EVIDENCE CUSTODY DETAILS
# ==============================================================================

@router.get("/evidence/{evidence_id}")
def get_evidence_custody_details(
    case_id: int,
    evidence_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Comprehensive evidence custody details:
    Returns evidence metadata, custody summary, current custody state, timeline, and transfer history.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, evidence_id, db)
    clean_ev_id = ev.evidence_id or str(ev.id)

    CustodyAdapter.sync_authentic_evidence_events(db, case_id, current_user)

    summary = CustodyService.get_custody_summary(db, clean_ev_id)
    current = CustodyService.get_current_custody(db, clean_ev_id, str(case_id))
    timeline = CustodyService.get_custody_timeline(db, evidence_id=clean_ev_id, case_id=str(case_id))
    transfers = CustodyService.get_transfer_history(db, evidence_id=clean_ev_id, case_id=str(case_id))

    return {
        "case_id": case_id,
        "evidence_id": clean_ev_id,
        "file_name": ev.file_name,
        "file_type": ev.file_type,
        "file_size": ev.file_size,
        "created_at": ev.created_at.isoformat() if ev.created_at else None,
        "status": ev.status,
        "summary": summary,
        "current_custody": current,
        "timeline": timeline,
        "transfers": transfers
    }
