from typing import List, Optional, Union, Dict, Any
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.report import (
    ReportOverviewResponse,
    ReportTrendItem,
    ReportTablePage,
    ReportStructuredViewResponse,
    ReportListResponse,
    ReportDetailResponse
)
from schemas.technical_report import ReportRequest, ReportGenerateResponse
from services.report_service import (
    get_investigator_reports_overview,
    get_investigator_reports_trend,
    get_investigator_reports_table,
    get_report_view_data,
    get_report_pdf_file_path,
    get_completed_reports,
    get_report_details,
    search_reports
)
from services.technical_report_service import TechnicalReportService

router = APIRouter(
    prefix="/reports",
    tags=["Reports"]
)


# ==============================================================================
# 1. REPORTS OVERVIEW COUNTS
# ==============================================================================

@router.get(
    "/overview",
    response_model=ReportOverviewResponse,
    summary="Get Reports Overview Counts",
    description="Returns genuine aggregated counts for Total, Ongoing, Completed/Final, Draft, and Not Generated reports."
)
def fetch_reports_overview(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_investigator_reports_overview(db, current_user)


# ==============================================================================
# 2. REPORTS TREND (LAST 6 MONTHS)
# ==============================================================================

@router.get(
    "/trend",
    response_model=List[ReportTrendItem],
    summary="Get Reports Trend Line Chart Data",
    description="Returns 6-month monthly report metrics (Reports Generated vs Final Reports) derived from genuine database records."
)
def fetch_reports_trend(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_investigator_reports_trend(db, current_user)


# ==============================================================================
# 3. SEARCH REPORTS
# ==============================================================================

@router.get(
    "/search",
    summary="Search Reports",
    description="Search reports by keyword across Case ID, Case Name, and Crime Type."
)
def search_report_endpoint(
    keyword: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return search_reports(db, keyword, current_user)


# ==============================================================================
# 4. CENTRALIZED PDF DOWNLOAD ENDPOINT (WORKS FOR ALL SCREENS)
# ==============================================================================

@router.get(
    "/download/{report_or_case_id}",
    summary="Download Forensic Report PDF",
    description="Centralized report download endpoint returning a genuine valid PDF with proper application/pdf Content-Type."
)
def download_report_by_path(
    report_or_case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    pdf_path, download_filename = get_report_pdf_file_path(db, report_or_case_id, current_user)
    return FileResponse(
        path=str(pdf_path),
        filename=download_filename,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{download_filename}"',
            "Content-Type": "application/pdf"
        }
    )


@router.get(
    "/{report_or_case_id}/download",
    summary="Download Forensic Report PDF (Alias)",
    description="Alternative centralized route matching /reports/{id}/download."
)
def download_report_alias(
    report_or_case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    pdf_path, download_filename = get_report_pdf_file_path(db, report_or_case_id, current_user)
    return FileResponse(
        path=str(pdf_path),
        filename=download_filename,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{download_filename}"',
            "Content-Type": "application/pdf"
        }
    )


# ==============================================================================
# 5. VIEW REPORT (STRUCTURED DETAILS)
# ==============================================================================

@router.get(
    "/{report_or_case_id}/view",
    response_model=ReportStructuredViewResponse,
    summary="View Structured Report Details",
    description="Returns complete structured report data across all 12+ forensic sections without raw JSON dumps."
)
def view_report_structured(
    report_or_case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_report_view_data(db, report_or_case_id, current_user)


# ==============================================================================
# 6. GENERATE REPORT DIRECTLY FROM REPORTS AREA
# ==============================================================================

@router.post(
    "/generate",
    response_model=ReportGenerateResponse,
    summary="Generate Forensic Report",
    description="Generates and permanently saves a ReportRecord in MySQL and writes persistent PDF to disk."
)
def generate_report_from_reports_module(
    payload: ReportRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    from routes.technical_report_routes import verify_case_report_access
    verify_case_report_access(payload.case_id, current_user, db)
    return TechnicalReportService.assemble_report_data(
        report=payload,
        db=db,
        current_user=current_user,
        is_draft=False
    )


# ==============================================================================
# 7. GET ALL REPORTS / TABLE (SEARCH, FILTER, PAGINATION)
# ==============================================================================

@router.get(
    "/",
    response_model=Union[ReportTablePage, List[ReportListResponse]],
    summary="Get Reports Table / List",
    description="Returns paginated, searchable, filterable table rows strictly scoped to the authenticated Investigator's assigned cases."
)
def fetch_reports(
    keyword: Optional[str] = None,
    case_status: Optional[str] = None,
    report_status: Optional[str] = None,
    crime_type: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    page: int = 1,
    page_size: int = 10,
    legacy: bool = False,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    # Check if legacy mode was explicitly requested
    is_legacy = (legacy is True or str(legacy).lower() in ("true", "1"))
    if is_legacy:
        return get_completed_reports(db, current_user)

    return get_investigator_reports_table(
        db=db,
        current_user=current_user,
        keyword=keyword,
        case_status=case_status,
        report_status=report_status,
        crime_type=crime_type,
        date_from=date_from,
        date_to=date_to,
        page=page,
        page_size=page_size
    )


# ==============================================================================
# 8. GET REPORT DETAILS BY CASE ID (BACKWARD COMPATIBILITY + VIEW)
# ==============================================================================

@router.get(
    "/{case_id}",
    summary="Get Report Details by Case ID or Report ID"
)
def fetch_report(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    return get_report_view_data(db, case_id, current_user)