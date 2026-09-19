from pathlib import Path
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse, StreamingResponse
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from models.evidence import Evidence
from utils.current_user import get_current_user
from services.epra_service import authorize_cyber_expert_case_access
from services.timeline_service import create_timeline_event
from services.metadata_service import MetadataService
from services.storage_service import StorageService
from services.backend_adapter import get_backend_adapter
from schemas.evidence_metadata import (
    MetadataExtractResponse,
    MetadataSummaryResponse,
    MetadataTableResponse,
    EvidenceDetailResponse
)

router = APIRouter(
    prefix="/cases",
    tags=["Metadata Extraction"]
)


@router.post(
    "/{case_id}/metadata/extract",
    response_model=MetadataExtractResponse,
    status_code=status.HTTP_200_OK,
    summary="Extract and synchronize metadata for all evidence in a case"
)
def extract_case_metadata(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Triggers Deepak's Metadata Extraction module on all evidence belonging to the selected case.
    - Idempotent and transaction-safe.
    - Resolves case by database ID or case code.
    - Enforces Cyber Expert authorization and assignment to the case.
    - Reuses existing Evidence records and SHA-256 baseline hashes.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)

    # Trigger Deepak's synchronization from adapter
    MetadataService.sync_case_from_adapter(db, str(case.case_id))

    # Retrieve updated summary
    summary_data = MetadataService.get_case_summary(db, str(case.case_id))

    # Record timeline event
    create_timeline_event(
        db=db,
        case_id=case.id,
        event="Evidence metadata extraction executed",
        performed_by=current_user.id,
        performed_by_role="Cyber Expert"
    )

    return MetadataExtractResponse(
        message="Evidence metadata extracted and synchronized successfully",
        case_id=str(case.case_id),
        total_synchronized=summary_data["total_files"],
        summary=summary_data
    )


@router.get(
    "/{case_id}/metadata",
    response_model=MetadataTableResponse,
    status_code=status.HTTP_200_OK,
    summary="Get paginated, searchable metadata table for case evidence"
)
def get_case_metadata_table(
    case_id: str,
    search: Optional[str] = Query(None, description="Search by filename, evidence ID, or file type"),
    sort_by: str = Query("id", description="Sort by 'filename', 'size', 'created', 'modified', or 'id'"),
    sort_order: str = Query("asc", description="'asc' or 'desc'"),
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Returns Deepak's searchable, paginated metadata table for the case.
    Row numbers, evidence IDs, filenames, display labels, formatted sizes,
    provenance timestamps, and backend-supplied hash verification statuses.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)

    return MetadataService.get_metadata_table(
        db=db,
        case_id=str(case.case_id),
        search=search,
        sort_by=sort_by,
        sort_order=sort_order,
        page=page,
        page_size=page_size
    )


@router.get(
    "/{case_id}/metadata/summary",
    response_model=MetadataSummaryResponse,
    status_code=status.HTTP_200_OK,
    summary="Get case metadata summary cards"
)
def get_case_metadata_summary(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Returns summary cards scoped to the case matching the approved UI:
    - Total Files
    - Total Size (bytes and formatted e.g. '1.42 GB')
    - Number of distinct file types
    - Latest upload timestamp
    - Hash verification metrics (verified, tampered, pending)
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)
    return MetadataService.get_case_summary(db, str(case.case_id))


@router.get(
    "/{case_id}/metadata/{evidence_id}",
    response_model=EvidenceDetailResponse,
    status_code=status.HTTP_200_OK,
    summary="Get detailed metadata and file properties for a specific evidence item"
)
def get_evidence_file_details(
    case_id: str,
    evidence_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Selected-file details card matching the approved UI right panel:
    Exact metadata, provenance timestamps, backend hash status,
    MIME type (guessed vs detected), and Pillow-extracted image properties.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)

    try:
        return MetadataService.get_file_details(db, evidence_id, case_id=str(case.case_id))
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get(
    "/{case_id}/metadata/{evidence_id}/download",
    summary="Download evidence file with safe path containment"
)
def download_evidence_file(
    case_id: str,
    evidence_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Controlled evidence file download with case scoping and safe path containment.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)

    adapter = get_backend_adapter()
    ev_item = adapter.get_evidence(evidence_id, case_id=str(case.case_id))
    if not ev_item:
        raise HTTPException(status_code=404, detail=f"Evidence #{evidence_id} not found in this case.")

    file_path, file_name, mime_type = StorageService.get_evidence_binary(ev_item, case)
    safe_filename = Path(file_name).name

    return FileResponse(
        path=str(file_path),
        filename=safe_filename,
        media_type=mime_type,
        headers={"Content-Disposition": f'attachment; filename="{safe_filename}"'}
    )


@router.get(
    "/{case_id}/metadata/{evidence_id}/preview",
    summary="Preview image evidence file"
)
def preview_evidence_file(
    case_id: str,
    evidence_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Controlled image preview stream.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)

    adapter = get_backend_adapter()
    ev_item = adapter.get_evidence(evidence_id, case_id=str(case.case_id))
    if not ev_item:
        raise HTTPException(status_code=404, detail=f"Evidence #{evidence_id} not found in this case.")

    file_path, file_name, mime_type = StorageService.get_evidence_binary(ev_item, case)

    return FileResponse(
        path=str(file_path),
        media_type=mime_type or "image/jpeg"
    )
