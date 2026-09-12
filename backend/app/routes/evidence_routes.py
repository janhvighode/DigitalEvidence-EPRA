from pathlib import Path
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, StreamingResponse
from sqlalchemy.orm import Session

from app.database import get_db, STORAGE_DIR
from app.services.metadata_service import MetadataService
from app.services.custody_service import CustodyService
from app.services.timeline_service import TimelineService
from app.services.hash_manifest_service import validate_safe_id
from app.services.backend_adapter import get_backend_adapter
from app.models.evidence_record import EvidenceRecord
from app.schemas.evidence_schema import (
    TransferInitiateRequest,
    TransferReceiveRequest,
    CurrentCustodyUpdateRequest
)

router = APIRouter(
    prefix="/evidence",
    tags=["Evidence Lifecycle, Metadata & Custody"]
)


# ==============================================================================
# 1. METADATA EXTRACTION ENDPOINTS (SCREENSHOT 1)
# ==============================================================================

@router.get("/case/{case_id}/summary")
def get_case_metadata_summary(
    case_id: str,
    db: Session = Depends(get_db)
):
    """
    Summary cards scoped to the case matching Screenshot 1:
    - Total Files
    - Total Size in bytes and formatted (e.g. '1.42 GB')
    - Number of distinct file types
    - Latest upload timestamp
    """
    try:
        clean_case_id = validate_safe_id(case_id, "case_id")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    return MetadataService.get_case_summary(db, clean_case_id)


@router.get("/case/{case_id}/metadata")
def get_case_metadata_table(
    case_id: str,
    search: Optional[str] = Query(None, description="Search by filename, evidence ID, or file type"),
    sort_by: str = Query("id", description="Sort by 'filename', 'size', 'created', 'modified', or 'id'"),
    sort_order: str = Query("asc", description="'asc' or 'desc'"),
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db)
):
    """
    Searchable, paginated metadata table matching Screenshot 1.
    Returns row numbers, evidence IDs, filenames, display labels, formatted sizes,
    provenance timestamps, and backend-supplied hash verification statuses.
    """
    try:
        clean_case_id = validate_safe_id(case_id, "case_id")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    return MetadataService.get_metadata_table(
        db=db,
        case_id=clean_case_id,
        search=search,
        sort_by=sort_by,
        sort_order=sort_order,
        page=page,
        page_size=page_size
    )


@router.get("/{evidence_id}/details")
@router.get("/{evidence_id}")
def get_evidence_file_details(
    evidence_id: str,
    db: Session = Depends(get_db)
):
    """
    Selected-file details card matching Screenshot 1 right panel.
    Returns exact metadata, provenance timestamps, backend hash status,
    MIME type (guessed vs detected), and Pillow-extracted image properties.
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
        return MetadataService.get_file_details(db, clean_ev_id)
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{evidence_id}/download")
def download_evidence_file(
    evidence_id: str,
    db: Session = Depends(get_db)
):
    """
    Controlled evidence file download.
    Enforces path containment within storage directory, preventing path traversal.
    Never accepts arbitrary client filesystem paths.
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # First check adapter file stream
    adapter = get_backend_adapter()
    stream_tuple = adapter.get_evidence_file_stream(clean_ev_id)
    if stream_tuple:
        stream, mime, size = stream_tuple
        ev_item = adapter.get_evidence(clean_ev_id)
        fname = ev_item.original_filename if ev_item else f"evidence_{clean_ev_id}.bin"
        return StreamingResponse(
            stream,
            media_type=mime,
            headers={"Content-Disposition": f'attachment; filename="{fname}"'}
        )

    # Fallback to local DB record
    record = db.query(EvidenceRecord).filter(
        (EvidenceRecord.external_evidence_id == clean_ev_id) |
        (EvidenceRecord.id == clean_ev_id if clean_ev_id.isdigit() else False)
    ).first()

    if not record or not record.file_path:
        raise HTTPException(status_code=404, detail=f"Evidence #{clean_ev_id} file not found.")

    target_path = Path(record.file_path).resolve()
    resolved_storage = STORAGE_DIR.resolve()

    if not target_path.is_relative_to(resolved_storage):
        raise HTTPException(status_code=403, detail="Access denied: file path outside safe evidence storage.")

    if not target_path.exists() or not target_path.is_file():
        raise HTTPException(status_code=404, detail="Evidence file not found on disk.")

    return FileResponse(
        path=str(target_path),
        filename=record.original_filename,
        media_type=record.mime_type or "application/octet-stream"
    )


@router.get("/{evidence_id}/preview")
def preview_evidence_file(
    evidence_id: str,
    db: Session = Depends(get_db)
):
    """
    Safe image preview endpoint for image evidence files.
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    # Check adapter stream
    adapter = get_backend_adapter()
    stream_tuple = adapter.get_evidence_file_stream(clean_ev_id)
    if stream_tuple:
        stream, mime, size = stream_tuple
        if "image" in mime:
            return StreamingResponse(stream, media_type=mime)

    record = db.query(EvidenceRecord).filter(
        (EvidenceRecord.external_evidence_id == clean_ev_id) |
        (EvidenceRecord.id == clean_ev_id if clean_ev_id.isdigit() else False)
    ).first()

    if not record or not record.file_path:
        raise HTTPException(status_code=404, detail=f"Evidence #{clean_ev_id} preview not available.")

    target_path = Path(record.file_path).resolve()
    resolved_storage = STORAGE_DIR.resolve()

    if not target_path.is_relative_to(resolved_storage):
        raise HTTPException(status_code=403, detail="Access denied: path traversal rejected.")

    if not target_path.exists() or not target_path.is_file():
        raise HTTPException(status_code=404, detail="Preview file not found.")

    suffix = target_path.suffix.lower()
    if suffix in (".jpg", ".jpeg"):
        media_type = "image/jpeg"
    elif suffix == ".png":
        media_type = "image/png"
    elif suffix == ".gif":
        media_type = "image/gif"
    elif suffix == ".webp":
        media_type = "image/webp"
    else:
        raise HTTPException(status_code=400, detail=f"Preview not supported for non-image file type: {suffix}")

    return FileResponse(path=str(target_path), media_type=media_type)


# ==============================================================================
# 2. CHAIN OF CUSTODY ENDPOINTS (SCREENSHOTS 2 & 3)
# ==============================================================================

@router.get("/{evidence_id}/custody/summary")
def get_evidence_custody_summary(
    evidence_id: str,
    db: Session = Depends(get_db)
):
    """
    Summary cards scoped to the evidence item matching Screenshot 2:
    - Total Events
    - Handlers (distinct human handlers, excluding system actions)
    - Transfers (completed)
    - First Handled timestamp
    - Current Status
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
        return CustodyService.get_custody_summary(db, clean_ev_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{evidence_id}/custody/timeline")
@router.get("/{evidence_id}/custody")
def get_evidence_custody_timeline(
    evidence_id: str,
    event_filter: Optional[str] = Query("ALL", description="Filter by event type: ALL, TRANSFERS, ACCESS, ANALYSIS, REPORT, ACQUISITION, UPLOAD, HASH"),
    db: Session = Depends(get_db)
):
    """
    Chronological custody timeline matching Screenshot 2.
    Filterable by event type and ordered deterministically.
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
        events = CustodyService.get_custody_timeline(db, clean_ev_id, event_filter)
        return {
            "evidence_id": clean_ev_id,
            "filter_applied": event_filter or "ALL",
            "total_events": len(events),
            "events": events
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{evidence_id}/custody/current")
def get_current_custody_info(
    evidence_id: str,
    db: Session = Depends(get_db)
):
    """
    Current Custody Information card matching Screenshot 2 right panel.
    Returns actual current holder, department, assigned on, last accessed, location, remarks,
    and current status. Returns null for unset fields (no invented defaults).
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
        return CustodyService.get_current_custody(db, clean_ev_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.put("/{evidence_id}/custody/current")
def update_current_custody_info(
    evidence_id: str,
    payload: CurrentCustodyUpdateRequest,
    db: Session = Depends(get_db)
):
    """
    Audited update of current custody location, department, or remarks.
    Holder changes cannot be performed via direct edit; holder changes MUST follow the transfer process!
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
        return CustodyService.update_current_custody(
            db=db,
            evidence_id=clean_ev_id,
            department=payload.department,
            location=payload.location,
            remarks=payload.remarks,
            actor_name=payload.actor_name,
            actor_id=payload.actor_id
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/{evidence_id}/transfers")
def get_transfer_history(
    evidence_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db)
):
    """
    Transfer history table matching Screenshot 2 right panel with pagination.
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
        return CustodyService.get_transfer_history(db, clean_ev_id, page=page, page_size=page_size)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/transfer/initiate")
def initiate_transfer(
    payload: TransferInitiateRequest,
    db: Session = Depends(get_db)
):
    """
    Initiate evidence transfer. Generates unique transfer reference.
    Enforces that evidence is marked PENDING_RECEIPT and cannot have contradictory transfers.
    Current holder does NOT change upon initiation.
    """
    try:
        clean_ev_id = validate_safe_id(str(payload.evidence_id), "evidence_id")
        res = CustodyService.initiate_transfer(
            db=db,
            evidence_id=clean_ev_id,
            sender_name=payload.sender_name,
            recipient_name=payload.recipient_name,
            remarks=payload.reason_or_remarks,
            sender_id=payload.sender_id,
            recipient_id=payload.recipient_id,
            sender_role=payload.sender_role,
            recipient_role=payload.recipient_role,
            case_id=payload.case_id
        )
        return res
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/transfer/receive")
def receive_transfer(
    payload: TransferReceiveRequest,
    transfer_reference: str = Query(..., description="Unique transfer reference token"),
    db: Session = Depends(get_db)
):
    """
    Confirm receipt of an in-flight transfer.
    Validates recipient and prevents duplicate receipt.
    Updates current holder officially upon confirmed receipt.
    Does NOT recalculate local file hashes.
    """
    try:
        res = CustodyService.receive_transfer(
            db=db,
            transfer_reference=transfer_reference,
            recipient_name=payload.recipient_name,
            recipient_id=payload.recipient_id,
            recipient_role=payload.recipient_role,
            department=payload.department,
            location=payload.location,
            remarks=payload.remarks
        )
        return res
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.post("/{evidence_id}/access")
def record_evidence_access(
    evidence_id: str,
    actor_name: str = Query("Investigator"),
    actor_id: Optional[str] = Query(None),
    actor_role: Optional[str] = Query("Cyber Expert"),
    purpose: str = Query("Forensic analysis inspection"),
    db: Session = Depends(get_db)
):
    """
    Record that evidence was accessed for analysis.
    Updates last_accessed timestamp and custody status to 'In Analysis'.
    """
    try:
        clean_ev_id = validate_safe_id(str(evidence_id), "evidence_id")
        return CustodyService.record_access_event(
            db=db,
            evidence_id=clean_ev_id,
            actor_name=actor_name,
            actor_id=actor_id,
            actor_role=actor_role,
            purpose=purpose
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ==============================================================================
# 3. TIMELINE RECONSTRUCTION
# ==============================================================================

@router.get("/case/{case_id}/timeline")
def get_case_timeline(case_id: str, db: Session = Depends(get_db)):
    """
    Reconstruct chronological investigation timeline for a case from real stored events.
    Deduplicates related events sharing the same event_reference.
    """
    try:
        clean_case_id = validate_safe_id(case_id, "case_id")
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    timeline = TimelineService.build_case_timeline(db, clean_case_id)
    return {
        "case_id": clean_case_id,
        "total_steps": len(timeline),
        "timeline": timeline
    }
