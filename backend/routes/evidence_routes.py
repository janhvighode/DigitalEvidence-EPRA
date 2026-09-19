from typing import List, Optional
from pathlib import Path
from fastapi import (
    APIRouter,
    Depends,
    UploadFile,
    File,
    Form,
    HTTPException,
    status
)
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.evidence import (
    EvidenceListItem,
    EvidenceUploadResponse,
    EvidenceBatchUploadResponse
)
from schemas.hash_verification import (
    CaseHashSummaryResponse,
    SingleEvidenceHashDetailsResponse
)
from services.evidence_service import (
    authorize_case_access,
    create_case_evidence,
    get_case_evidence_list,
    get_evidence_details,
    get_case_evidence_download,
    ingest_zip_evidence_batch
)
from services.hash_verification_service import HashVerificationService
from services.storage_service import StorageService
from services.epra_service import normalize_epra_evidence_type


router = APIRouter(
    prefix="/cases",
    tags=["Evidence & Hash Verification"]
)


# ============================================================
# 1. CASE HASH SUMMARY
# ============================================================

@router.get(
    "/{case_id}/hash-verification/summary",
    response_model=CaseHashSummaryResponse
)
def fetch_case_hash_summary(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns case-wise hash summary metrics (Total, Verified, Tampered, Pending)
    for the selected case only. Scoped strictly by role and case assignment.
    """
    case = authorize_case_access(db, case_id, current_user)
    return HashVerificationService.get_case_hash_summary(db, case)


# ============================================================
# 2. CASE EVIDENCE LIST
# ============================================================

@router.get(
    "/{case_id}/evidence",
    response_model=List[EvidenceListItem]
)
def fetch_case_evidence(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns list of digital evidence files belonging strictly to the selected case.
    """
    case = authorize_case_access(db, case_id, current_user)
    return get_case_evidence_list(db, case)


# ============================================================
# 3. SINGLE EVIDENCE HASH DETAILS
# ============================================================

@router.get(
    "/{case_id}/evidence/{evidence_id}/hash-verification",
    response_model=SingleEvidenceHashDetailsResponse
)
def fetch_evidence_hash_details(
    case_id: str,
    evidence_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns detailed forensic verification results for a single evidence item,
    including current SHA-256, reference hash, and integrity status.
    """
    case = authorize_case_access(db, case_id, current_user)
    return get_evidence_details(db, case, evidence_id)


# ============================================================
# 4. EVIDENCE INGESTION / UPLOAD
# ============================================================

@router.post(
    "/{case_id}/evidence",
    response_model=EvidenceUploadResponse,
    status_code=status.HTTP_201_CREATED
)
async def upload_evidence(
    case_id: str,
    file: UploadFile = File(...),
    original_hash: Optional[str] = Form(None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Authenticated evidence upload for a selected case:
    - Verifies case access for current_user
    - Saves file to isolated storage
    - Runs Member 5 HashService to generate real SHA-256
    - Records Evidence and EvidenceHash entities
    """
    case = authorize_case_access(db, case_id, current_user)

    file_data = await StorageService.save_uploaded_file(file, case.id)

    new_evidence, new_hash = create_case_evidence(
        db=db,
        case=case,
        file_data=file_data,
        current_user=current_user,
        original_hash=original_hash
    )

    return EvidenceUploadResponse(
        message="Evidence uploaded and SHA-256 hash computed successfully",
        evidence_id=new_evidence.evidence_id,
        file_name=new_evidence.file_name,
        file_size=new_evidence.file_size,
        current_hash=new_hash.current_hash,
        integrity_status=new_hash.integrity_status
    )


# ============================================================
# 5. BATCH EVIDENCE INGESTION (ADMIN ZIP ARCHIVE)
# ============================================================

@router.post(
    "/{case_id}/evidence/batch",
    response_model=EvidenceBatchUploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Batch evidence ingestion from a secure ZIP archive (Administrator only)"
)
async def upload_evidence_batch(
    case_id: str,
    archive: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Authenticated batch evidence ingestion for a selected case:
    - Enforces Administrator role (role_id == 1) and Cyber Cell branch scoping.
    - Securely validates archive integrity, Zip Slip, file counts, and compression bombs.
    - Extracts individual files to isolated case storage.
    - Computes genuine SHA-256 for EACH extracted member file.
    - Atomically creates individual Evidence and EvidenceHash records.
    - Adds 1 batch timeline event and user-scoped batch notifications.
    - The ZIP container itself does NOT become an evidence item.
    """
    if current_user.role_id != 1:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrator access required for batch evidence ingestion"
        )

    case = authorize_case_access(db, case_id, current_user)

    return await ingest_zip_evidence_batch(
        db=db,
        case=case,
        archive=archive,
        current_user=current_user
    )


# ============================================================
# 6. EVIDENCE DOWNLOAD
# ============================================================

@router.get(
    "/{case_id}/evidence/{evidence_id}/download",
    summary="Download Original Evidence File",
    description="Securely downloads the authentic original evidence file from persistent storage with case scoping and integrity protection."
)
def download_evidence(
    case_id: str,
    evidence_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Authenticated evidence download:
    - Verifies case access for current_user
    - Resolves evidence record by canonical ID or PK
    - Retrieves real original binary from durable storage
    - Returns original binary with proper Content-Type and Content-Disposition headers
    """
    file_path, file_name, media_type = get_case_evidence_download(
        db=db,
        case_identifier=case_id,
        evidence_identifier=evidence_id,
        current_user=current_user
    )
    safe_filename = Path(file_name).name
    return FileResponse(
        path=str(file_path),
        filename=safe_filename,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{safe_filename}"'}
    )


# ============================================================
# 7. EVIDENCE PREVIEW
# ============================================================

@router.get(
    "/{case_id}/evidence/{evidence_id}/preview",
    summary="Preview Image Evidence File",
    description="Streams previewable image evidence file inline with role-based case authorization."
)
def preview_evidence(
    case_id: str,
    evidence_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Authenticated image evidence preview:
    - Verifies case access for current_user (Cyber Expert, Investigator, Admin)
    - Validates that evidence is an image format
    - Retrieves real original binary from durable storage
    - Returns original binary inline with proper image Content-Type
    """
    case = authorize_case_access(db, case_id, current_user)
    file_path, file_name, media_type = get_case_evidence_download(
        db=db,
        case_identifier=case_id,
        evidence_identifier=evidence_id,
        current_user=current_user
    )

    # Validate image format for preview
    canonical_type = normalize_epra_evidence_type(filename=file_name, file_type=media_type)
    if canonical_type != "IMAGE" and not (media_type and media_type.lower().startswith("image/")):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Preview is only supported for image evidence. Evidence '{file_name}' is of type '{canonical_type}'."
        )

    safe_filename = Path(file_name).name
    return FileResponse(
        path=str(file_path),
        filename=safe_filename,
        media_type=media_type or "image/jpeg",
        headers={"Content-Disposition": f'inline; filename="{safe_filename}"'}
    )


