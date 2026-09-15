from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.case_status import (
    CaseStatusBoardResponse,
    CaseStatusDetailResponse,
    CaseStatusUpdateRequest,
    CaseStatusUpdateResponse,
    StatusHistoryItem
)
from services.case_status_service import (
    get_investigator_case_status_board,
    get_investigator_case_status_detail,
    update_case_status_by_investigator,
    get_investigator_case_status_history
)


router = APIRouter(
    prefix="/investigator",
    tags=["Investigator Case Status"]
)


def verify_investigator(current_user: User) -> User:
    """Enforces authentication and strict Investigator (role_id == 2) authorization."""
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
# 1. INVESTIGATOR CASE STATUS BOARD
# ==============================================================================

@router.get(
    "/case-status",
    response_model=CaseStatusBoardResponse,
    summary="Investigator Case Status Board",
    description="Returns Kanban sections (OPEN, IN_PROGRESS, UNDER_REVIEW, CLOSED) and counts strictly scoped to cases assigned to the authenticated investigator."
)
def fetch_case_status_board(
    search: Optional[str] = Query(None, description="Search by Case ID, title, or crime type"),
    status: Optional[str] = Query(None, description="Filter by status (OPEN, IN_PROGRESS, UNDER_REVIEW, CLOSED)"),
    priority: Optional[str] = Query(None, description="Filter by priority (Low, Medium, High, Critical)"),
    case_health: Optional[str] = Query(None, description="Filter by health (ON_TRACK, NEEDS_ATTENTION, BLOCKED)"),
    report_status: Optional[str] = Query(None, description="Filter by report status (NOT_GENERATED, DRAFT, GENERATED, FINAL)"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(10, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_case_status_board(
        db=db,
        current_user=current_user,
        search=search,
        status_filter=status,
        priority=priority,
        case_health_filter=case_health,
        report_status_filter=report_status,
        page=page,
        page_size=page_size
    )


# ==============================================================================
# 2. CASE STATUS EXPANDED / DETAIL
# ==============================================================================

@router.get(
    "/case-status/{case_id}",
    response_model=CaseStatusDetailResponse,
    summary="Investigator Case Status Detail",
    description="Returns detailed case information, evidence summary, module readiness, case health, next-stage recommendations, and status history."
)
def fetch_case_status_detail(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_case_status_detail(
        db=db,
        case_identifier=case_id,
        current_user=current_user
    )


# ==============================================================================
# 3. CHANGE CASE STATUS
# ==============================================================================

@router.patch(
    "/cases/{case_id}/status",
    response_model=CaseStatusUpdateResponse,
    summary="Change Case Status",
    description="Updates the single-source Case.status field with strict state-machine transition validation and transactional audit logging."
)
def change_case_status(
    case_id: str,
    payload: CaseStatusUpdateRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return update_case_status_by_investigator(
        db=db,
        case_identifier=case_id,
        new_status_raw=payload.new_status,
        remark=payload.remark,
        current_user=current_user
    )


# ==============================================================================
# 4. STATUS HISTORY
# ==============================================================================

@router.get(
    "/cases/{case_id}/status-history",
    response_model=List[StatusHistoryItem],
    summary="Get Case Status History",
    description="Returns chronological audit trail of all status transitions for the case."
)
def fetch_case_status_history(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_case_status_history(
        db=db,
        case_identifier=case_id,
        current_user=current_user
    )
