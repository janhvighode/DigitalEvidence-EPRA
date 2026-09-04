from pathlib import Path

from reportlab.platypus import SimpleDocTemplate
from reportlab.platypus import Paragraph
from reportlab.platypus import Spacer
from reportlab.lib.styles import getSampleStyleSheet


class PDFService:

    @staticmethod
    def generate_pdf(report):

        # Create uploads folder inside backend/app if it doesn't exist
        upload_dir = Path(__file__).parent.parent / "uploads"
        upload_dir.mkdir(parents=True, exist_ok=True)

        # PDF file path
        filename = upload_dir / f"{report['case_id']}.pdf"

        styles = getSampleStyleSheet()

        pdf = SimpleDocTemplate(str(filename))

        story = []

        # -------------------------------
        # Report Title
        # -------------------------------
        story.append(
            Paragraph(
                "<b>DIGITAL EVIDENCE REPORT</b>",
                styles["Title"]
            )
        )

        story.append(Spacer(1, 20))

        # -------------------------------
        # Case Details
        # -------------------------------
        story.append(
            Paragraph(
                f"<b>Case ID :</b> {report['case_id']}",
                styles["BodyText"]
            )
        )

        story.append(
            Paragraph(
                f"<b>Case Title :</b> {report['case_title']}",
                styles["BodyText"]
            )
        )

        story.append(
            Paragraph(
                f"<b>Investigator :</b> {report['investigator_name']}",
                styles["BodyText"]
            )
        )

        story.append(
            Paragraph(
                f"<b>Suspect :</b> {report['suspect_name']}",
                styles["BodyText"]
            )
        )

        story.append(
            Paragraph(
                f"<b>Evidence Count :</b> {report['evidence_count']}",
                styles["BodyText"]
            )
        )

        story.append(Spacer(1, 20))

        # -------------------------------
        # Timeline
        # -------------------------------
        story.append(
            Paragraph(
                "<b>Timeline</b>",
                styles["Heading2"]
            )
        )

        for item in report["timeline"]:
            story.append(
                Paragraph(
                    f"{item['step']}. {item['event']} ({item['timestamp']})",
                    styles["BodyText"]
                )
            )

        story.append(Spacer(1, 20))

        # -------------------------------
        # Activity Log
        # -------------------------------
        story.append(
            Paragraph(
                "<b>Activity Log</b>",
                styles["Heading2"]
            )
        )

        for log in report["activity"]:
            story.append(
                Paragraph(
                    f"{log['activity']} - {log['time']}",
                    styles["BodyText"]
                )
            )

        # Build PDF
        pdf.build(story)

        return str(filename)