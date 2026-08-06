from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List


# ==========================
# Report List Schema
# ==========================

class ReportListResponse(BaseModel):
    case_id: str
    title: str
    investigator_name: str
    priority: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


# ==========================
# Timeline Event Schema
# ==========================

class TimelineEvent(BaseModel):
    event: str
    performed_by_role: str
    created_at: datetime

    class Config:
        from_attributes = True


# ==========================
# Report Detail Schema
# ==========================

class ReportDetailResponse(BaseModel):
    case_id: str
    title: str
    description: Optional[str]

    investigator_name: str

    priority: str
    status: str

    created_at: datetime
    updated_at: datetime

    # Timeline
    timeline: List[TimelineEvent] = []

    # Future Modules
    epra_score: Optional[float] = None
    cbir_match: Optional[float] = None
    evidence_count: Optional[int] = None
    chain_of_custody: Optional[str] = None

    report_generated: bool = False

    class Config:
        from_attributes = True