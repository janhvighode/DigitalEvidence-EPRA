"""
pdf_generator.py

Generates professional PDF investigation reports.
"""

from pathlib import Path

from reportlab.lib.units import inch
from reportlab.lib.styles import getSampleStyleSheet
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle
)
from reportlab.lib import colors


class PDFGenerator:

    @staticmethod
    def export(report_data,
               output_directory="generated_reports"):

        output_directory = Path(output_directory)

        output_directory.mkdir(exist_ok=True)

        output_file = (
            output_directory /
            "Investigation_Report.pdf"
        )

        doc = SimpleDocTemplate(
            str(output_file)
        )

        styles = getSampleStyleSheet()

        story = []

        # ----------------------------------
        # Title
        # ----------------------------------

        story.append(

            Paragraph(

                report_data["report_title"],

                styles["Title"]

            )

        )

        story.append(Spacer(1, 0.25 * inch))

        # ----------------------------------
        # Generated Time
        # ----------------------------------

        story.append(

            Paragraph(

                f"<b>Generated:</b> "
                f"{report_data['generated_at']}",

                styles["Normal"]

            )

        )

        story.append(Spacer(1, 0.2 * inch))

        # ----------------------------------
        # Summary
        # ----------------------------------

        story.append(

            Paragraph(

                "<b>Investigation Summary</b>",

                styles["Heading2"]

            )

        )

        summary = report_data["summary"]

        summary_table = [

            ["Total Evidence",
             summary["total_evidence"]],

            ["Total Suspects",
             summary["total_suspects"]],

            ["Critical",
             summary["critical"]],

            ["High",
             summary["high"]],

            ["Medium",
             summary["medium"]],

            ["Low",
             summary["low"]],

            ["Very Low",
             summary["very_low"]]

        ]

        table = Table(summary_table)

        table.setStyle(

            TableStyle([

                ("GRID",(0,0),(-1,-1),1,
                 colors.black),

                ("BACKGROUND",
                 (0,0),
                 (-1,0),
                 colors.lightgrey),

                ("BOTTOMPADDING",
                 (0,0),
                 (-1,-1),
                 6)

            ])

        )

        story.append(table)

        story.append(Spacer(1,0.3*inch))

        # ----------------------------------
        # Evidence Ranking
        # ----------------------------------

        story.append(

            Paragraph(

                "<b>Evidence Ranking</b>",

                styles["Heading2"]

            )

        )

        evidence_table = [[

            "Rank",

            "File",

            "Type",

            "Score",

            "Priority"

        ]]

        for evidence in report_data["evidence"]:

            evidence_table.append([

                evidence["rank"],

                evidence["file_name"],

                evidence["evidence_type"],

                evidence["epra_score"],

                evidence["priority"]

            ])

        table = Table(evidence_table)

        table.setStyle(

            TableStyle([

                ("GRID",(0,0),(-1,-1),1,
                 colors.black),

                ("BACKGROUND",
                 (0,0),
                 (-1,0),
                 colors.grey),

                ("TEXTCOLOR",
                 (0,0),
                 (-1,0),
                 colors.white),

                ("ALIGN",
                 (0,0),
                 (-1,-1),
                 "CENTER")

            ])

        )

        story.append(table)

        story.append(Spacer(1,0.3*inch))

        # ----------------------------------
        # Suspects
        # ----------------------------------

        story.append(

            Paragraph(

                "<b>Suspect Ranking</b>",

                styles["Heading2"]

            )

        )

        suspect_table = [[

            "Rank",

            "Suspect",

            "Evidence",

            "Score"

        ]]

        for suspect in report_data["suspects"]:

            suspect_table.append([

                suspect["rank"],

                suspect["suspect_name"],

                suspect["linked_evidence"],

                suspect["total_epra_score"]

            ])

        table = Table(suspect_table)

        table.setStyle(

            TableStyle([

                ("GRID",(0,0),(-1,-1),1,
                 colors.black),

                ("BACKGROUND",
                 (0,0),
                 (-1,0),
                 colors.darkblue),

                ("TEXTCOLOR",
                 (0,0),
                 (-1,0),
                 colors.white),

                ("ALIGN",
                 (0,0),
                 (-1,-1),
                 "CENTER")

            ])

        )

        story.append(table)

        # ----------------------------------
        # External Integration Status
        # ----------------------------------
        has_pending = any(
            e.get("pending_external_inputs") for e in report_data.get("evidence", [])
        )

        if has_pending:
            story.append(Spacer(1, 0.3 * inch))
            story.append(
                Paragraph(
                    "<b>External Integration Status</b>",
                    styles["Heading2"]
                )
            )

            pending_rows = [["File", "Dimension", "Integration Status"]]
            for ev in report_data["evidence"]:
                for dim, status in ev.get("pending_external_inputs", {}).items():
                    pending_rows.append([ev["file_name"], dim, status])

            if len(pending_rows) > 1:
                ptable = Table(pending_rows)
                ptable.setStyle(
                    TableStyle([
                        ("GRID", (0, 0), (-1, -1), 1, colors.black),
                        ("BACKGROUND", (0, 0), (-1, 0), colors.darkorange),
                        ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
                        ("ALIGN", (0, 0), (-1, -1), "LEFT"),
                        ("FONTSIZE", (0, 0), (-1, -1), 8)
                    ])
                )
                story.append(ptable)

        doc.build(story)

        return output_file