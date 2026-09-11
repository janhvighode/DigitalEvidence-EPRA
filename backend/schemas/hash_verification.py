from pydantic import BaseModel
from datetime import datetime
from typing import Optional


class CaseHashSummaryResponse(BaseModel):
    case_id: str
    case_name: str
    status: str
    total_evidence: int
    verified: int
    tampered: int
    pending: int

    class Config:
        from_attributes = True


class SingleEvidenceHashDetailsResponse(BaseModel):
    evidence_id: str
    file_name: str
    file_type: str
    file_size: int
    uploaded_on: datetime
    file_path: Optional[str] = None
    current_hash: str
    original_hash: Optional[str] = None
    hash_match: Optional[bool] = None
    tampered: Optional[bool] = None
    integrity_status: str
    verification_date: Optional[datetime] = None
    verified_by: Optional[str] = None

    class Config:
        from_attributes = True
