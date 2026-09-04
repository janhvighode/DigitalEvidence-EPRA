from app.schemas.report_schema import ReportRequest
from app.services.report_service import ReportService
from app.services.timeline_service import TimelineService
from app.services.activity_service import ActivityService
from app.services.pdf_service import PDFService


def run_test():

    report = ReportRequest(

        case_id="CASE-2026-001",

        case_title="Cyber Fraud Investigation",

        investigator_name="Deepak Sharma",

        suspect_name="John Doe",

        evidence_count=5,

        events=[
            "FIR Registered",
            "Mobile Seized",
            "Laptop Seized",
            "SHA-256 Hash Generated",
            "Evidence Verified",
            "Report Generated"
        ]

    )

    timeline = TimelineService.generate_timeline(
        report.case_id,
        report.events
    )

    activity = ActivityService.generate_activity_log(
        report.investigator_name,
        report.events
    )

    report_data = ReportService.generate_report(
        report,
        timeline,
        activity
    )

    pdf = PDFService.generate_pdf(report_data)

    print("=" * 60)
    print("REPORT MODULE TEST SUCCESS")
    print("=" * 60)
    print("Generated PDF :", pdf)


if __name__ == "__main__":
    run_test()