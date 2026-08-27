from pydantic import BaseModel


class DashboardStats(BaseModel):
    total_cases: int
    evidence_files: int
    high_priority: int
    pending_analysis: int


class RecentCase(BaseModel):
    case_id: str
    title: str
    status: str


class PrioritySummary(BaseModel):
    high: int
    medium: int
    low: int