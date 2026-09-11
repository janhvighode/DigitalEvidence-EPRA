from pydantic import BaseModel
from datetime import datetime


class EvidenceListItem(BaseModel):
    evidence_id: str
    file_name: str
    file_type: str
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
