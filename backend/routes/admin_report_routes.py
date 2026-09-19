from typing import Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user
from services.admin_report_service import AdminReportService
from schemas.admin_report import (
    AdminCaseReportItem,
    AdminCaseReportPage,
    AdminReportCoverageResponse,
    AdminReportHistoryResponse
)

router = APIRouter(
    prefix="/admin/reports",
    tags=["Admin Reports"]
)


@router.get(
    "/cases",
    response_model=AdminCaseReportPage,
    summary="Get Case-Wise Reports for Administrator",
    description="Returns paginated, searchable, filterable, and sortable case-wise report monitoring data strictly scoped to the Administrator's cyber cell."
)
def get_admin_case_wise_reports(
    search: Optional[str] = Query(None, description="Search by Case ID, Case Title, Investigator, Cyber Expert"),
    case_status: Optional[str] = Query(None, description="Filter by Case Status: Open, In Progress, Under Review, Closed"),
    report_status: Optional[str] = Query(None, description="Filter by Report Status: NOT_GENERATED, DRAFT, GENERATED, FINAL"),
    sort: Optional[str] = Query("recent", description="Sort order: recent, oldest, case_id, latest_report"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(10, ge=1, le=100, description="Page size"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return AdminReportService.get_case_wise_reports(
        db=db,
        current_user=current_user,
        search=search,
        case_status=case_status,
        report_status=report_status,
        sort=sort,
        page=page,
        page_size=page_size
    )


@router.get(
    "/coverage",
    response_model=AdminReportCoverageResponse,
    summary="Get Case-Based Report Coverage Summary",
    description="Returns dynamic summary of case-based report coverage (total cases, cases with reports, cases without reports, coverage percentage, and status distribution)."
)
def get_admin_report_coverage(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return AdminReportService.get_report_coverage(
        db=db,
        current_user=current_user
    )


@router.get(
    "/cases/{case_id}",
    response_model=AdminCaseReportItem,
    summary="Get Single Case Report Overview",
    description="Returns report overview, latest report metadata, and journey milestones for an authorized case."
)
def get_admin_case_report_overview(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return AdminReportService.get_case_report_overview(
        db=db,
        case_id=case_id,
        current_user=current_user
    )


@router.get(
    "/cases/{case_id}/history",
    response_model=AdminReportHistoryResponse,
    summary="Get All Persisted Reports for Case (Report History)",
    description="Returns all persisted reports (drafts, generated, final) for an authorized case, ordered newest to oldest."
)
def get_admin_case_report_history(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return AdminReportService.get_case_report_history(
        db=db,
        case_id=case_id,
        current_user=current_user
    )
