from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from typing import List

from database.database import get_db

from services.system_statistics_service import (
    get_epra_statistics,
    get_cbir_statistics,
    get_investigator_performance,
    get_case_progress_trend,
    get_priority_analysis
)

from schemas.system_statistics import (
    EPRAStatisticsResponse,
    CBIRStatisticsResponse,
    InvestigatorPerformanceResponse,
    CaseTrendResponse,
    PriorityAnalysisResponse
)

router = APIRouter(
    prefix="/statistics",
    tags=["System Statistics"]
)


# =====================================
# EPRA Analytics
# =====================================
@router.get(
    "/epra",
    response_model=EPRAStatisticsResponse
)
def epra_statistics(db: Session = Depends(get_db)):
    return get_epra_statistics(db)


# =====================================
# CBIR Statistics
# =====================================
@router.get(
    "/cbir",
    response_model=CBIRStatisticsResponse
)
def cbir_statistics(db: Session = Depends(get_db)):
    return get_cbir_statistics(db)


# =====================================
# Investigator Performance
# =====================================
@router.get(
    "/investigators",
    response_model=List[InvestigatorPerformanceResponse]
)
def investigator_statistics(db: Session = Depends(get_db)):
    return get_investigator_performance(db)


# =====================================
# Case Progress Trend
# =====================================
@router.get(
    "/case-trend",
    response_model=List[CaseTrendResponse]
)
def case_progress_statistics(db: Session = Depends(get_db)):
    return get_case_progress_trend(db)


# =====================================
# Priority Analysis
# =====================================
@router.get(
    "/priority",
    response_model=PriorityAnalysisResponse
)
def priority_statistics(db: Session = Depends(get_db)):
    return get_priority_analysis(db)