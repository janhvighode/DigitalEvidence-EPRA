from pydantic import BaseModel
from typing import Optional


class DashboardStats(BaseModel):
    total_cases: int
    pending_registration_requests: int
    total_users: int
    open_cases: int

    # For Total Statistics chart
    in_progress_cases: int
    under_review_cases: int
    closed_cases: int


class RecentCase(BaseModel):
    id: int
    case_id: str
    title: str
    status: str
    priority: Optional[str] = None
    investigator_name: Optional[str] = None
    updated_at: Optional[str] = None


class PrioritySummary(BaseModel):
    high: int
    medium: int
    low: int