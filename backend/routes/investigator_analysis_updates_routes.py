from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.investigator_analysis_updates import (
    AnalysisUpdatesSummaryResponse,
    CaseAnalysisOverviewItem,
    CaseAnalysisOverviewPage,
    AnalysisPulsePage,
)
from services.investigator_analysis_updates_service import InvestigatorAnalysisUpdatesService


router = APIRouter(
    prefix="/investigator/analysis-updates",
    tags=["Investigator - Analysis Updates"]
)


def verify_investigator(current_user: User) -> User:
    """
    Strict Investigator Role Authorization:
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
# 1. SUMMARY ENDPOINT
# ==============================================================================

@router.get(
    "/summary",
    response_model=AnalysisUpdatesSummaryResponse,
    status_code=status.HTTP_200_OK,
    summary="Get overall analysis updates summary for assigned cases"
)
def fetch_analysis_updates_summary(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns case-level analysis update totals strictly for cases assigned
    to the logged-in Investigator (Case.investigator_id == current_user.id).
    """
    verify_investigator(current_user)
    return InvestigatorAnalysisUpdatesService.get_analysis_updates_summary(
        db=db,
        current_user=current_user
    )


# ==============================================================================
# 2. CASE ANALYSIS OVERVIEW (LIST WITH FILTERS & PAGINATION)
# ==============================================================================

@router.get(
    "/cases",
    response_model=CaseAnalysisOverviewPage,
    status_code=status.HTTP_200_OK,
    summary="Get case-level forensic analysis overview across assigned cases"
)
def fetch_cases_analysis_overview(
    search: Optional[str] = Query(None, description="Search by Case ID, title, or crime description"),
    analysis_state: Optional[str] = Query(None, description="Filter by derived state: ALL, IN_ANALYSIS, ATTENTION_REQUIRED, COMPLETED, PENDING"),
    attention_required: Optional[bool] = Query(None, description="Filter for cases requiring immediate attention (true/false)"),
    case_status: Optional[str] = Query(None, description="Filter by case status: Open, In Progress, Under Review, Closed"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(10, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns all cases assigned to the logged-in Investigator with complete
    case-level analysis information: progress percentage (excluding N/A modules),
    individual module states (Integrity, Metadata, EPRA, CBIR, Entity Ranking,
    Relationship, Technical Report), intelligence summary, latest update, and attention reasons.
    """
    verify_investigator(current_user)

    clean_search = search if isinstance(search, str) else None
    clean_state = analysis_state if isinstance(analysis_state, str) else None
    clean_attention = attention_required if isinstance(attention_required, bool) else None
    clean_status = case_status if isinstance(case_status, str) else None
    clean_page = page if isinstance(page, int) and page >= 1 else 1
    clean_size = page_size if isinstance(page_size, int) and page_size >= 1 else 10

    return InvestigatorAnalysisUpdatesService.get_cases_analysis_overview(
        db=db,
        current_user=current_user,
        search=clean_search,
        analysis_state=clean_state,
        attention_required=clean_attention,
        case_status=clean_status,
        page=clean_page,
        page_size=clean_size
    )


# ==============================================================================
# 3. SINGLE CASE ANALYSIS OVERVIEW
# ==============================================================================

@router.get(
    "/cases/{case_id}",
    response_model=CaseAnalysisOverviewItem,
    status_code=status.HTTP_200_OK,
    summary="Get case-level analysis overview for a single assigned case"
)
def fetch_single_case_analysis_overview(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Retrieves deep analysis summary for a specific assigned case.
    Rejects unauthorized or cross-investigator access with 403.
    """
    verify_investigator(current_user)
    return InvestigatorAnalysisUpdatesService.get_single_case_analysis_overview(
        db=db,
        current_user=current_user,
        case_identifier=case_id
    )


# ==============================================================================
# 4. ANALYSIS PULSE (RECENT ACTIVITY)
# ==============================================================================

@router.get(
    "/activity",
    response_model=AnalysisPulsePage,
    status_code=status.HTTP_200_OK,
    summary="Get chronological Analysis Pulse activity feed across assigned cases"
)
def fetch_analysis_pulse_activity(
    module: Optional[str] = Query(None, description="Optional module filter: EPRA, INTEGRITY, CBIR, METADATA, ENTITY_RANKING, RELATIONSHIP, TECHNICAL_REPORT"),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(20, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns recent case-level forensic analysis events across all cases assigned
    to the logged-in Investigator, ordered strictly newest first.
    """
    verify_investigator(current_user)

    clean_mod = module if isinstance(module, str) else None
    clean_page = page if isinstance(page, int) and page >= 1 else 1
    clean_limit = limit if isinstance(limit, int) and limit >= 1 else 20

    return InvestigatorAnalysisUpdatesService.get_analysis_pulse_activity(
        db=db,
        current_user=current_user,
        module=clean_mod,
        limit=clean_limit,
        page=clean_page
    )
