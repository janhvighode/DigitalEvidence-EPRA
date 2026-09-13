from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.investigator_dashboard import (
    InvestigatorDashboardStats,
    CaseRequiringAttentionItem,
    InvestigatorEvidenceStatusResponse,
    CaseStatusDistributionResponse,
    InvestigatorMyCasesPage
)
from services.investigator_dashboard_service import (
    get_investigator_dashboard_stats,
    get_cases_requiring_attention,
    get_evidence_status,
    get_case_status_distribution,
    get_investigator_my_cases
)


router = APIRouter(
    prefix="/investigator",
    tags=["Investigator Dashboard & Cases"]
)


def verify_investigator(current_user: User) -> User:
    """
    Enforces strict Investigator role authorization:
    - User must be authenticated
    - User must have role_id == 2 (Investigator)
    """
    if not current_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )

    if current_user.role_id != 2:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Investigator access required"
        )

    return current_user


# ==============================================================================
# 1. SUMMARY STATS (7 CARDS)
# ==============================================================================

@router.get(
    "/dashboard/stats",
    response_model=InvestigatorDashboardStats,
    summary="Get Investigator Dashboard Stats",
    description="Returns 7 genuine summary metrics strictly scoped to the authenticated investigator."
)
def fetch_dashboard_stats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_dashboard_stats(db, current_user)


# ==============================================================================
# 2. CASES REQUIRING ATTENTION
# ==============================================================================

@router.get(
    "/dashboard/cases-requiring-attention",
    response_model=List[CaseRequiringAttentionItem],
    summary="Get Cases Requiring Attention",
    description="Returns assigned cases requiring immediate attention due to tampered evidence, critical EPRA, or high priority."
)
def fetch_cases_requiring_attention(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_cases_requiring_attention(db, current_user)


# ==============================================================================
# 3. EVIDENCE STATUS BREAKDOWN
# ==============================================================================

@router.get(
    "/dashboard/evidence-status",
    response_model=InvestigatorEvidenceStatusResponse,
    summary="Get Evidence Status Breakdown",
    description="Returns evidence integrity and analysis status metrics across all assigned cases."
)
def fetch_evidence_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_evidence_status(db, current_user)


# ==============================================================================
# 4. CASE STATUS DISTRIBUTION
# ==============================================================================

@router.get(
    "/dashboard/case-status-distribution",
    response_model=CaseStatusDistributionResponse,
    summary="Get Case Status Distribution",
    description="Returns case counts by status (Open, In Progress, Under Review, Closed) for assigned cases."
)
def fetch_case_status_distribution(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_case_status_distribution(db, current_user)


# ==============================================================================
# 5. MY ASSIGNED CASES
# ==============================================================================

@router.get(
    "/my-cases",
    response_model=InvestigatorMyCasesPage,
    summary="Get Investigator Assigned Cases",
    description="Returns paginated assigned cases for the investigator with search, status, priority, and cyber expert filters."
)
def fetch_investigator_my_cases(
    search: Optional[str] = Query(None, description="Search by case ID, title, or description"),
    status: Optional[str] = Query(None, description="Filter by status (Open, In Progress, Under Review, Closed)"),
    priority: Optional[str] = Query(None, description="Filter by priority (Low, Medium, High, Critical)"),
    cyber_expert_id: Optional[int] = Query(None, description="Filter by assigned Cyber Expert user ID"),
    start_date: Optional[str] = Query(None, description="Filter cases created on or after this ISO date"),
    end_date: Optional[str] = Query(None, description="Filter cases created on or before this ISO date"),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(10, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_my_cases(
        db=db,
        current_user=current_user,
        search=search,
        status=status,
        priority=priority,
        cyber_expert_id=cyber_expert_id,
        start_date=start_date,
        end_date=end_date,
        page=page,
        limit=limit
    )
