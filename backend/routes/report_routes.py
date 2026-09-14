from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from services.report_service import (
    get_completed_reports,
    get_report_details,
    search_reports
)

from schemas.report import (
    ReportListResponse,
    ReportDetailResponse
)

router = APIRouter(
    prefix="/reports",
    tags=["Reports"]
)


# ==========================================
# Get All Reports
# ==========================================

@router.get(
    "/",
    response_model=List[ReportListResponse]
)
def fetch_reports(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_completed_reports(db, current_user)


# ==========================================
# Search Reports
# ==========================================

@router.get("/search")
def search_report(
    keyword: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return search_reports(db, keyword, current_user)


# ==========================================
# View Report Details
# ==========================================

@router.get(
    "/{case_id}",
    response_model=ReportDetailResponse
)
def fetch_report(
    case_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    report = get_report_details(db, case_id, current_user)

    if report is None:
        raise HTTPException(
            status_code=404,
            detail="Report not found or access denied"
        )

    return report


# ==========================================
# Download Report (Placeholder)
# ==========================================

@router.get("/{case_id}/download")
def download_report(
    case_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    report = get_report_details(db, case_id, current_user)

    if report is None:
        raise HTTPException(
            status_code=404,
            detail="Report not found or access denied"
        )

    return {
        "message": "PDF generation will be integrated after Report Generation module is completed.",
        "case_id": case_id
    }