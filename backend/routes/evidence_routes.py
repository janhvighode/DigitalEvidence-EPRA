from typing import List, Optional
from fastapi import (
    APIRouter,
    Depends,
    UploadFile,
    File,
    Form,
    status
)
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.evidence import (
    EvidenceListItem,
    EvidenceUploadResponse
)
from schemas.hash_verification import (
    CaseHashSummaryResponse,
    SingleEvidenceHashDetailsResponse
)
from services.evidence_service import (
    authorize_case_access,
    create_case_evidence,
    get_case_evidence_list,
    get_evidence_details
)
from services.hash_verification_service import HashVerificationService
from services.storage_service import StorageService


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
