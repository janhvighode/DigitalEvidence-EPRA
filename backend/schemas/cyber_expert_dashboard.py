from pydantic import BaseModel
from datetime import datetime


class CyberExpertDashboardStats(BaseModel):
    assigned_cases: int
    pending_cases: int
    under_analysis: int
    completed_cases: int


class CyberExpertCaseResponse(BaseModel):
    id: int
    case_id: str
    title: str
    priority: str
    status: str
    created_at: datetime
    updated_at: datetime | None = None


class CyberExpertCaseStatus(BaseModel):
    pending: int
    under_analysis: int
    completed: int