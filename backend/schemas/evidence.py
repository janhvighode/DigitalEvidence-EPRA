from typing import List, Optional
from datetime import datetime
from pydantic import BaseModel


class EvidenceListItem(BaseModel):
    evidence_id: str
    file_name: str
    file_type: str
    evidence_type: Optional[str] = None
    file_size: int
    uploaded_on: datetime
    current_hash: str
    integrity_status: str

    class Config:
        from_attributes = True


class EvidenceUploadResponse(BaseModel):
    message: str
    evidence_id: str
    file_name: str
    file_size: int
    current_hash: str
    integrity_status: str

    class Config:
        from_attributes = True


class EvidenceBatchItem(BaseModel):
    evidence_id: str
    file_name: str
    file_type: str
    file_size: int
    sha256_hash: str
    current_hash: str
    integrity_status: str
    uploaded_on: Optional[datetime] = None

    class Config:
        from_attributes = True


class EvidenceBatchUploadResponse(BaseModel):
    success: bool
    message: str
    case_id: str
    archive_name: str
    archive_size: int
    archive_hash: str
    total_files: int
    items: List[EvidenceBatchItem]

    class Config:
        from_attributes = True
