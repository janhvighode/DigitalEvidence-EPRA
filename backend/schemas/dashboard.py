from pydantic import BaseModel
from typing import Optional


class DashboardStats(BaseModel):
    total_users: int
    total_cases: int

    open_cases: int
    in_progress_cases: int
    under_review_cases: int
    closed_cases: int

    # Existing fields rakhe hain so frontend break na ho
    evidence_files: int = 0
    high_priority: int
    pending_analysis: int


class RecentCase(BaseModel):
    id: int
    case_id: str
    title: str
    status: str
    priority: Optional[str] = None


class PrioritySummary(BaseModel):
    high: int
    medium: int
    low: int