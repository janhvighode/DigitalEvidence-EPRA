import re
from pathlib import Path
from typing import Optional
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse, JSONResponse
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from models.case import Case
from models.report_record import ReportRecord
from utils.current_user import get_current_user

from schemas.technical_report import (
    ReportRequest,
    ReportSummaryResponse,
    ReportHistoryResponse,
    ReportGenerateResponse
)
from services.technical_report_service import TechnicalReportService
from services.pdf_service import DEFAULT_REPORTS_DIR

router = APIRouter(
    prefix="/cases/{case_id}/reports",
    tags=["Technical Reports"]
)

REPORT_ID_REGEX = re.compile(r"^[a-zA-Z0-9_\-]+$")


def validate_report_id(report_id: str) -> str:
    if not report_id or not isinstance(report_id, str):
        raise HTTPException(status_code=400, detail="Report ID must be a non-empty string.")
    cleaned = report_id.strip()
    if not REPORT_ID_REGEX.match(cleaned):
        raise HTTPException(status_code=400, detail="Invalid Report ID format.")
    return cleaned


def verify_cyber_expert_case_access(case_id: str | int, current_user: User, db: Session) -> Case:
    """
    Enforce Cyber Expert authorization and assigned case boundary.
    - Missing/invalid JWT -> 401
    - Role != Cyber Expert (role_id != 3) -> 403 Forbidden
    - Case not found -> 404 Not Found
    - Case not assigned to current Cyber Expert -> 403 Forbidden
    """
    if not current_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )
    if current_user.role_id != 3:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to Cyber Experts only"
        )

    clean_id = str(case_id).strip()
    if clean_id.isdigit():
        case = db.query(Case).filter(
            (Case.id == int(clean_id)) | (Case.case_id == clean_id)
        ).first()
    else:
        case = db.query(Case).filter(
            Case.case_id == clean_id
        ).first()

    if not case:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Case #{case_id} not found"
        )

    if case.cyber_expert_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"You are not assigned to Case #{case_id}"
        )

    return case


def verify_report_read_access(case_id: str | int, current_user: User, db: Session) -> Case:
    """
    Enforce authorization and assigned case boundary for viewing and downloading reports:
    - Missing/invalid JWT -> 401
    - Role == 3 (Cyber Expert): Must be assigned (Case.cyber_expert_id == current_user.id)
    - Role == 2 (Investigator): Must be assigned (Case.investigator_id == current_user.id)
    - Otherwise -> 403 Forbidden
    """
    if not current_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )

    clean_id = str(case_id).strip()
    if clean_id.isdigit():
        case = db.query(Case).filter(
            (Case.id == int(clean_id)) | (Case.case_id == clean_id)
        ).first()
    else:
        case = db.query(Case).filter(
            Case.case_id == clean_id
        ).first()

    if not case:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Case #{case_id} not found"
        )

    if current_user.role_id == 3:
        if case.cyber_expert_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"You are not assigned as Cyber Expert to Case #{case_id}"
            )
        return case
    elif current_user.role_id == 2:
        if case.investigator_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=f"You are not assigned as Investigator to Case #{case_id}"
            )
        return case
    else:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to assigned Cyber Experts and Investigators only"
        )


@router.get("/summary", response_model=ReportSummaryResponse)
def get_case_reporting_summary(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Case summary cards for Technical Report generation screen:
    - Total Evidence
    - Verified Evidence
    - Tampered Evidence
    - Pending Verification
    - Unknown Outcome
    Derived dynamically from real evidence integrity records.
    """
    verify_report_read_access(case_id, current_user, db)
    return TechnicalReportService.get_case_reporting_summary(db, str(case_id))


@router.post("/preview")
def preview_report(
    case_id: str,
    report: ReportRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Generate an actual draft preview from selected report type, sections, and real case data.
    Marked with DRAFT watermark; does NOT register preview as finalized report in database or create custody events.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    report.case_id = str(case_id)

    try:
        res = TechnicalReportService.assemble_report_data(
            report=report,
            db=db,
            current_user=current_user,
            is_draft=True
        )
        if res.get("file_format") == "JSON":
            return JSONResponse(content=res["manifest_content"])
        else:
            pdf_path = Path(res["pdf_path"])
            return FileResponse(
                path=str(pdf_path),
                filename=pdf_path.name,
                media_type="application/pdf"
            )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.post("/generate", response_model=ReportGenerateResponse)
def generate_report(
    case_id: str,
    payload: Optional[ReportRequest] = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Generate a final report (PDF or JSON manifest).
    Pulls real case evidence records, baseline hashes, and verification statuses without recalculating.
    Persists an immutable ReportRecord version and creates custody/activity audit logs.
    """
    verify_cyber_expert_case_access(case_id, current_user, db)
    report = payload or ReportRequest(case_id=str(case_id))
    report.case_id = str(case_id)

    try:
        res = TechnicalReportService.assemble_report_data(
            report=report,
            db=db,
            current_user=current_user,
            is_draft=False
        )
        return res
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=str(e))


@router.get("/history", response_model=ReportHistoryResponse)
def get_report_history(
    case_id: str,
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Previous report history for this case:
    - Report ID, Name, Generated At, Generated By, Report Type, Format, Size, Preview URL, Download URL.
    Supports stable sorting and pagination.
    """
    verify_report_read_access(case_id, current_user, db)
    return TechnicalReportService.get_report_history(db, str(case_id), page=page, page_size=page_size)


@router.get("/preview/{report_id}")
def preview_existing_report(
    case_id: str,
    report_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Preview an existing finalized report by ID.
    Enforces case scoping and path containment within safe storage directory.
    """
    case = verify_report_read_access(case_id, current_user, db)
    clean_id = validate_report_id(report_id)

    record = db.query(ReportRecord).filter(ReportRecord.id == clean_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Report #{clean_id} not found.")

    # Strict Case Scoping: Prevent cross-case report access
    allowed_case_ids = {str(case_id), str(case.id), str(case.case_id)}
    if record.case_id not in allowed_case_ids:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Report #{clean_id} does not belong to Case #{case_id}."
        )

    target_path = Path(record.file_path).resolve()
    resolved_storage_root = DEFAULT_REPORTS_DIR.parent.resolve()

    if not target_path.is_relative_to(resolved_storage_root):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: report outside safe storage.")

    if not target_path.exists() or not target_path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report file not found on disk.")

    media_type = "application/json" if record.file_format == "JSON" else "application/pdf"
    return FileResponse(
        path=str(target_path),
        filename=target_path.name,
        media_type=media_type
    )


@router.get("/download/{report_id}")
def download_report_by_id(
    case_id: str,
    report_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Safely download a generated report by report ID.
    Strictly enforces case scoping and path containment within safe storage directory.
    """
    case = verify_report_read_access(case_id, current_user, db)
    clean_id = validate_report_id(report_id)

    record = db.query(ReportRecord).filter(ReportRecord.id == clean_id).first()
    if not record:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Report #{clean_id} not found.")

    # Strict Case Scoping: Prevent cross-case report access
    allowed_case_ids = {str(case_id), str(case.id), str(case.case_id)}
    if record.case_id not in allowed_case_ids:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Report #{clean_id} does not belong to Case #{case_id}."
        )

    target_path = Path(record.file_path).resolve()
    resolved_storage_root = DEFAULT_REPORTS_DIR.parent.resolve()

    if not target_path.is_relative_to(resolved_storage_root):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Access denied: report outside safe storage.")

    if not target_path.exists() or not target_path.is_file():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Report file not found on disk.")

    media_type = "application/json" if record.file_format == "JSON" else "application/pdf"
    return FileResponse(
        path=str(target_path),
        filename=target_path.name,
        media_type=media_type
    )
