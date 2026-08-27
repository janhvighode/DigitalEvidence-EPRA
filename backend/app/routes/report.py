from fastapi import APIRouter, HTTPException
from fastapi.responses import FileResponse

from app.schemas.report_schema import ReportRequest
from app.services.timeline_service import TimelineService
from app.services.activity_service import ActivityService
from app.services.report_service import ReportService
from app.services.pdf_service import PDFService

router = APIRouter(
    prefix="/report",
    tags=["Report Module"]
)


@router.post("/generate")
def generate_report(report: ReportRequest):

    try:

        # Generate Timeline
        timeline = TimelineService.generate_timeline(
            report.case_id,
            report.events
        )

        # Generate Activity Log
        activity = ActivityService.generate_activity_log(
            report.investigator_name,
            report.events
        )

        # Prepare Report Data
        report_data = ReportService.generate_report(
            report,
            timeline,
            activity
        )

        # Generate PDF
        pdf_path = PDFService.generate_pdf(report_data)

        return {
            "status": "success",
            "message": "Report generated successfully.",
            "pdf_path": pdf_path
        }

    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=str(e)
        )


@router.get("/download")
def download_report(path: str):

    return FileResponse(
        path=path,
        filename="Investigation_Report.pdf",
        media_type="application/pdf"
    )


@router.get("/health")
def health():

    return {
        "module": "Report Module",
        "status": "Running"
    }