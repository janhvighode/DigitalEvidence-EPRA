from pydantic import BaseModel


class EPRAStatisticsResponse(BaseModel):
    overall_health: float

    total_evidence: int

    high_priority: int
    medium_priority: int
    low_priority: int
    pending_analysis: int

    average_epra_score: float
    highest_score: float
    lowest_score: float

    class Config:
        from_attributes = True


class CBIRStatisticsResponse(BaseModel):
    total_images: int
    matched_images: int
    failed_matches: int
    match_rate: float

    class Config:
        from_attributes = True


class InvestigatorPerformanceResponse(BaseModel):
    investigator_name: str
    assigned_cases: int
    completed_cases: int
    active_cases: int
    completion_percentage: float


class CaseTrendResponse(BaseModel):
    month: str
    created_cases: int
    closed_cases: int


class PriorityAnalysisResponse(BaseModel):
    high_priority: int
    medium_priority: int
    low_priority: int