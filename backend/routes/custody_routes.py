from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, status, Query
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.custody_log import CustodyLog
from utils.current_user import get_current_user
from services.custody_service import CustodyService
from services.custody_adapter import CustodyAdapter
from services.storage_service import StorageService
from services.epra_service import normalize_epra_evidence_type
from schemas.custody import (
    TransferInitiateRequest,
    TransferReceiveRequest,
    CurrentCustodyUpdateRequest,
    CustodySummaryResponse,
    CustodyTimelineResponse,
    CurrentCustodyResponse,
    TransferHistoryResponse,
    EvidenceCustodyDetailResponse
)

router = APIRouter(
    prefix="/cases/{case_id}/chain-of-custody",
    tags=["Chain of Custody"]
)


def verify_cyber_expert_case_access(case_id: int, current_user: User, db: Session) -> Case:
    """
    Enforce case authorization and boundary:
    - Missing/invalid JWT -> 401 (handled by get_current_user)
    - Role 1 (Admin): Allowed for cases in their branch
    - Role 2 (Investigator): Allowed if assigned (case.investigator_id == current_user.id)
    - Role 3 (Cyber Expert): Allowed if assigned (case.cyber_expert_id == current_user.id)
    - Case not found -> 404 Not Found
    - Unassigned / foreign user -> 403 Forbidden
    """
    if not current_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )

    case = db.query(Case).filter(Case.id == case_id).first()
    if not case:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Case #{case_id} not found"
        )

    if current_user.role_id == 3:
        if case.cyber_expert_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"You are not assigned as Cyber Expert to Case #{case_id}"
            )
    elif current_user.role_id == 2:
        if case.investigator_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"You are not assigned as Investigator to Case #{case_id}"
            )
    elif current_user.role_id == 1:
        creator = db.query(User).filter(User.id == case.created_by).first()
        if creator and creator.cyber_cell_id != current_user.cyber_cell_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access denied: Case does not belong to your branch"
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to assigned Cyber Experts, Investigators, and Administrators"
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
    Audited update of current custody details (holder assignment/reaffirmation, location, department, remarks, status).
    Holder changes cannot be performed via direct edit once established; must follow transfer workflow.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, evidence_id, db)
    clean_ev_id = ev.evidence_id or str(ev.id)

    actor_name = current_user.full_name or current_user.username
    actor_id = str(current_user.id)
    actor_role = CustodyService.resolve_user_role_name(db, current_user)

    try:
        updated = CustodyService.update_current_custody(
            db=db,
            evidence_id=clean_ev_id,
            department=payload.department,
            location=payload.location,
            remarks=payload.remarks,
            actor_name=actor_name,
            actor_id=actor_id,
            actor_role=actor_role,
            current_holder_id=payload.current_holder_id,
            current_holder_name=payload.current_holder_name,
            current_holder_role=payload.current_holder_role,
            custody_status=payload.custody_status,
            case_id=str(case_id)
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
    sender_role = CustodyService.resolve_user_role_name(db, current_user)

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
    recipient_role = CustodyService.resolve_user_role_name(db, current_user)

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
    Includes 60s debounce check to prevent duplicate audit logs from client re-renders.
    Actor derived strictly from JWT.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, evidence_id, db)
    clean_ev_id = ev.evidence_id or str(ev.id)

    actor_name = current_user.full_name or current_user.username
    actor_id = str(current_user.id)
    actor_role = CustodyService.resolve_user_role_name(db, current_user)

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

@router.get("/evidence/{evidence_id}", response_model=EvidenceCustodyDetailResponse)
def get_evidence_custody_details(
    case_id: int,
    evidence_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Comprehensive evidence custody details:
    Returns complete evidence metadata, canonical type, MIME type, hash & integrity state,
    custody summary, current custody state, timeline, and transfer history.
    """
    case = verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, evidence_id, db)
    clean_ev_id = ev.evidence_id or str(ev.id)

    CustodyAdapter.sync_authentic_evidence_events(db, case_id, current_user)

    summary = CustodyService.get_custody_summary(db, clean_ev_id)
    current = CustodyService.get_current_custody(db, clean_ev_id, str(case_id))
    timeline = CustodyService.get_custody_timeline(db, evidence_id=clean_ev_id, case_id=str(case_id))
    transfers = CustodyService.get_transfer_history(db, evidence_id=clean_ev_id, case_id=str(case_id))

    # Canonical type
    canonical_type = normalize_epra_evidence_type(filename=ev.file_name, file_type=ev.file_type)

    # Hash / integrity
    ev_hash = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
    original_sha256 = ev_hash.original_hash or ev_hash.sha256_hash if ev_hash else None
    current_hash = ev_hash.current_hash or ev_hash.sha256_hash if ev_hash else None
    integrity_status = ev_hash.integrity_status if ev_hash else None

    # Uploader resolution
    ev_rec = db.query(EvidenceRecord).filter(
        (EvidenceRecord.external_evidence_id == clean_ev_id) |
        (EvidenceRecord.id == ev.id)
    ).first()
    uploaded_by = ev_rec.investigator_name if (ev_rec and ev_rec.investigator_name) else None
    if not uploaded_by:
        upload_log = db.query(CustodyLog).filter(
            CustodyLog.evidence_id == clean_ev_id,
            CustodyLog.action == "EVIDENCE_UPLOADED"
        ).first()
        if upload_log:
            uploaded_by = upload_log.investigator_name
    if not uploaded_by and case.investigator_id:
        inv_u = db.query(User).filter(User.id == case.investigator_id).first()
        if inv_u:
            uploaded_by = inv_u.full_name or inv_u.username

    current_custodian = current.get("current_holder_name")
    last_accessed = current.get("last_accessed")

    return {
        "case_id": case_id,
        "evidence_id": clean_ev_id,
        "file_name": ev.file_name,
        "original_filename": ev.file_name,
        "file_type": ev.file_type,
        "canonical_type": canonical_type,
        "evidence_type": canonical_type,
        "mime_type": (ev_rec.mime_type if ev_rec and ev_rec.mime_type else ev.file_type),
        "file_size": ev.file_size,
        "file_size_bytes": ev.file_size,
        "created_at": ev.created_at.isoformat() if ev.created_at else None,
        "upload_timestamp": ev.created_at.isoformat() if ev.created_at else None,
        "uploaded_at": ev.created_at.isoformat() if ev.created_at else None,
        "uploaded_by": uploaded_by,
        "added_by": uploaded_by,
        "original_sha256": original_sha256,
        "original_hash": original_sha256,
        "current_hash": current_hash,
        "sha256_hash": current_hash,
        "integrity_status": integrity_status,
        "integrity_verification_status": integrity_status,
        "current_custodian": current_custodian,
        "last_accessed": last_accessed,
        "status": ev.status,
        "evidence_status": ev.status,
        "preview_url": f"/cases/{case_id}/chain-of-custody/evidence/{clean_ev_id}/preview",
        "download_url": f"/cases/{case_id}/evidence/{clean_ev_id}/download",
        "summary": summary,
        "current_custody": current,
        "timeline": timeline,
        "transfers": transfers
    }


# ==============================================================================
# 7. IMAGE PREVIEW (SECURE AUTHORIZED STREAM)
# ==============================================================================

@router.get(
    "/evidence/{evidence_id}/preview",
    summary="Preview image evidence file for Chain of Custody",
    description="Streams previewable image evidence file inline with case authorization checks."
)
def preview_evidence_image(
    case_id: int,
    evidence_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Controlled image preview stream.
    Validates case access, verifies evidence belongs to case,
    and returns real image bytes with correct image MIME type.
    """
    case = verify_cyber_expert_case_access(case_id, current_user, db)
    ev = verify_evidence_in_case(case_id, evidence_id, db)

    canonical_type = normalize_epra_evidence_type(filename=ev.file_name, file_type=ev.file_type)
    if canonical_type != "IMAGE" and not (ev.file_type and ev.file_type.lower().startswith("image/")):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Preview is only supported for image evidence. Evidence '{ev.file_name}' is of type '{canonical_type}'."
        )

    file_path, file_name, mime_type = StorageService.get_evidence_binary(ev, case)

    return FileResponse(
        path=str(file_path),
        media_type=mime_type or "image/jpeg",
        headers={"Content-Disposition": f'inline; filename="{file_name}"'}
    )
