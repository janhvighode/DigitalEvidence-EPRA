from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from services.dashboard_service import (
    get_dashboard_stats,
    get_recent_cases,
    get_priority_summary,
)

router = APIRouter(
    prefix="/dashboard",
    tags=["Dashboard"]
)


@router.get("/stats")
def dashboard_stats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_dashboard_stats(
        db,
        current_user
    )


@router.get("/recent-cases")
def recent_cases(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_recent_cases(
        db,
        current_user
    )


@router.get("/priority")
def priority_summary(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_priority_summary(
        db,
        current_user
    )