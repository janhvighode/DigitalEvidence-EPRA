from fastapi import APIRouter
from services.dashboard_service import (
    get_dashboard_stats,
    get_recent_cases,
    get_priority_summary,
)

router = APIRouter(prefix="/dashboard", tags=["Dashboard"])


@router.get("/stats")
def dashboard_stats():
    return get_dashboard_stats()


@router.get("/recent-cases")
def recent_cases():
    return get_recent_cases()


@router.get("/priority")
def priority_summary():
    return get_priority_summary()