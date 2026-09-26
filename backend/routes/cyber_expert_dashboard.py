from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

from database.database import get_db

from models.user import User
from utils.current_user import get_current_user

from services.cyber_expert_dashboard_service import (
    get_cyber_expert_dashboard_stats,
    get_cyber_expert_cases,
    get_cyber_expert_case_status
)

from schemas.cyber_expert_dashboard import (
    CyberExpertDashboardStats,
    CyberExpertCaseResponse,
    CyberExpertCaseStatus
)


router = APIRouter(
    prefix="/cyber-expert/dashboard",
    tags=["Cyber Expert Dashboard"]
)


def verify_cyber_expert(current_user: User):

    if current_user.role_id != 3:
        raise HTTPException(
            status_code=403,
            detail="Cyber Expert access required"
        )


# ==========================================
# DASHBOARD CARDS
# ==========================================

@router.get(
    "/stats",
    response_model=CyberExpertDashboardStats
)
def dashboard_stats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    verify_cyber_expert(current_user)

    return get_cyber_expert_dashboard_stats(
        db,
        current_user
    )


# ==========================================
# MY / ASSIGNED CASES
# ==========================================

@router.get(
    "/cases",
    response_model=List[CyberExpertCaseResponse]
)
def assigned_cases(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    verify_cyber_expert(current_user)

    return get_cyber_expert_cases(
        db,
        current_user
    )


# ==========================================
# CASE STATUS CHART
# ==========================================

@router.get(
    "/case-status",
    response_model=CyberExpertCaseStatus
)
def case_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    verify_cyber_expert(current_user)

    return get_cyber_expert_case_status(
        db,
        current_user
    )