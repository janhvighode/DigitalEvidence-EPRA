"""
FastAPI Routes for Administrator -> System Statistics.
Requires Administrator JWT authentication (role_id == 1).
Provides aggregated forensic system statistics scoped strictly to the Admin's Cyber Cell.
"""
from datetime import date
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.admin_system_statistics import (
    EPRAStatisticsResponse,
    CBIRStatisticsResponse,
    InvestigatorStatisticsResponse,
    CaseTrendResponse,
    PriorityAnalysisResponse,
    ForensicSummaryResponse,
    AdminSystemStatisticsSummaryResponse,
)
from services.admin_system_statistics_service import AdminSystemStatisticsService

router = APIRouter(
    prefix="/admin/system-statistics",
    tags=["Administrator - System Statistics"]
)


def verify_administrator(current_user: User = Depends(get_current_user)) -> User:
    """Ensure the authenticated user is an Administrator (role_id == 1)."""
    if current_user.role_id != 1:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Administrator access required"
        )
    return current_user


def validate_date_range(
    start_date: Optional[date] = Query(None, description="Start date (YYYY-MM-DD)"),
    end_date: Optional[date] = Query(None, description="End date (YYYY-MM-DD)")
) -> tuple[Optional[date], Optional[date]]:
    """Validate that start_date <= end_date."""
    if start_date and end_date and start_date > end_date:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="start_date must be before or equal to end_date"
        )
    return start_date, end_date


# =====================================================================
# 1. EXECUTIVE SUMMARY
# =====================================================================

@router.get(
    "/summary",
    response_model=AdminSystemStatisticsSummaryResponse,
    summary="Executive Dashboard Summary Cards"
)
def get_system_statistics_summary(
    dates: tuple[Optional[date], Optional[date]] = Depends(validate_date_range),
    current_user: User = Depends(verify_administrator),
    db: Session = Depends(get_db)
):
    start_date, end_date = dates
    return AdminSystemStatisticsService.get_system_statistics_summary(
        db=db,
        current_user=current_user,
        start_date=start_date,
        end_date=end_date
    )


# =====================================================================
# 2. EPRA ANALYTICS
# =====================================================================

@router.get(
    "/epra",
    response_model=EPRAStatisticsResponse,
    summary="EPRA Priority and Coverage Analytics"
)
def get_epra_statistics(
    dates: tuple[Optional[date], Optional[date]] = Depends(validate_date_range),
    current_user: User = Depends(verify_administrator),
    db: Session = Depends(get_db)
):
    start_date, end_date = dates
    return AdminSystemStatisticsService.get_epra_statistics(
        db=db,
        current_user=current_user,
        start_date=start_date,
        end_date=end_date
    )


# =====================================================================
# 3. CBIR STATISTICS
# =====================================================================

@router.get(
    "/cbir",
    response_model=CBIRStatisticsResponse,
    summary="Content-Based Image Retrieval Visual Similarity Statistics"
)
def get_cbir_statistics(
    dates: tuple[Optional[date], Optional[date]] = Depends(validate_date_range),
    current_user: User = Depends(verify_administrator),
    db: Session = Depends(get_db)
):
    start_date, end_date = dates
    return AdminSystemStatisticsService.get_cbir_statistics(
        db=db,
        current_user=current_user,
        start_date=start_date,
        end_date=end_date
    )


# =====================================================================
# 4. INVESTIGATOR PERFORMANCE
# =====================================================================

@router.get(
    "/investigators",
    response_model=InvestigatorStatisticsResponse,
    summary="Investigator Operational Workload and Completion Metrics"
)
def get_investigator_statistics(
    dates: tuple[Optional[date], Optional[date]] = Depends(validate_date_range),
    current_user: User = Depends(verify_administrator),
    db: Session = Depends(get_db)
):
    start_date, end_date = dates
    return AdminSystemStatisticsService.get_investigator_performance(
        db=db,
        current_user=current_user,
        start_date=start_date,
        end_date=end_date
    )


# =====================================================================
# 5. CASE PROGRESS TRENDS
# =====================================================================

@router.get(
    "/case-trends",
    response_model=CaseTrendResponse,
    summary="Case Intake vs Closure Timeline Trends"
)
def get_case_trends(
    dates: tuple[Optional[date], Optional[date]] = Depends(validate_date_range),
    current_user: User = Depends(verify_administrator),
    db: Session = Depends(get_db)
):
    start_date, end_date = dates
    return AdminSystemStatisticsService.get_case_progress_trend(
        db=db,
        current_user=current_user,
        start_date=start_date,
        end_date=end_date
    )


# =====================================================================
# 6. PRIORITY ANALYSIS
# =====================================================================

@router.get(
    "/priorities",
    response_model=PriorityAnalysisResponse,
    summary="Separated Case Triage and EPRA Evidence Priority Distributions"
)
def get_priority_analysis(
    dates: tuple[Optional[date], Optional[date]] = Depends(validate_date_range),
    current_user: User = Depends(verify_administrator),
    db: Session = Depends(get_db)
):
    start_date, end_date = dates
    return AdminSystemStatisticsService.get_priority_analysis(
        db=db,
        current_user=current_user,
        start_date=start_date,
        end_date=end_date
    )


# =====================================================================
# 7. FORENSIC MODULE SUMMARY
# =====================================================================

@router.get(
    "/forensic-summary",
    response_model=ForensicSummaryResponse,
    summary="Aggregated Counts Across Integrity, Metadata, Suspect Entities, Links, and Reports"
)
def get_forensic_summary(
    dates: tuple[Optional[date], Optional[date]] = Depends(validate_date_range),
    current_user: User = Depends(verify_administrator),
    db: Session = Depends(get_db)
):
    start_date, end_date = dates
    return AdminSystemStatisticsService.get_forensic_summary(
        db=db,
        current_user=current_user,
        start_date=start_date,
        end_date=end_date
    )
