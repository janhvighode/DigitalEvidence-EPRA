import os
import html
from pathlib import Path
from uuid import uuid4
from datetime import datetime, timezone
from typing import Dict, Any, List, Optional

from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.platypus import (
    SimpleDocTemplate,
    Paragraph,
    Spacer,
    Table,
    TableStyle,
    KeepTogether,
    PageBreak,
    HRFlowable
)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.pdfgen import canvas

DEFAULT_REPORTS_DIR = Path(__file__).resolve().parent.parent / "generated_reports" / "reports"
DEFAULT_REPORTS_DIR.mkdir(parents=True, exist_ok=True)


class NumberedCanvas(canvas.Canvas):
    """
    Two-pass canvas to dynamically compute and print 'Page X of Y' footer.
    """
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._saved_page_states = []

    def showPage(self):
        self._saved_page_states.append(dict(self.__dict__))
        self._startPage()

    def save(self):
        num_pages = len(self._saved_page_states)
        for state in self._saved_page_states:
            self.__dict__.update(state)
            self.draw_footer(num_pages)
            super().showPage()
        super().save()

    def draw_footer(self, page_count):
        self.saveState()
        self.setFont("Helvetica", 8)
        self.setFillColor(colors.HexColor("#555555"))
        footer_text = f"Page {self._pageNumber} of {page_count}  |  CONFIDENTIAL DIGITAL FORENSIC REPORT  |  ePRA SYSTEM v2.0"
        self.drawRightString(612 - 36, 25, footer_text)
        self.restoreState()


class PDFService:

    @staticmethod
    def _safe_text(val: Any) -> str:
        """Escape XML entities for ReportLab Paragraphs."""
        if val is None:
            return "N/A"
        return html.escape(str(val))

    @classmethod
    def generate_pdf(
        cls,
        report_data: Dict[str, Any],
        output_directory: Optional[str] = None,
        is_draft: bool = False
    ) -> str:
        """
        Generate a comprehensive, multipage, beautifully formatted PDF report.
        Strictly renders only the selected sections.
        """
        if output_directory:
            report_dir = Path(output_directory)
        else:
            report_dir = DEFAULT_REPORTS_DIR

        report_dir.mkdir(parents=True, exist_ok=True)

        report_id = report_data.get("report_id") or str(uuid4())
        case_id = str(report_data.get("case_id", "UNKNOWN_CASE"))
        prefix = "draft_preview" if is_draft else "report"
        filename = report_dir / f"{prefix}_{case_id}_{report_id}.pdf"

        # Document setup: 0.5 inch (36pt) margins
        doc = SimpleDocTemplate(
            str(filename),
            pagesize=letter,
            leftMargin=36,
            rightMargin=36,
            topMargin=40,
            bottomMargin=45
        )

        base_styles = getSampleStyleSheet()

        title_style = ParagraphStyle(
            "CoverTitle",
            parent=base_styles["Title"],
            fontSize=20,
            leading=24,
            textColor=colors.HexColor("#0f172a"),
            alignment=0
        )
        h2_style = ParagraphStyle(
            "SectionH2",
            parent=base_styles["Heading2"],
            fontSize=11,
            leading=14,
            textColor=colors.HexColor("#1e3a8a"),
            spaceBefore=14,
            spaceAfter=6,
            keepWithNext=True
        )
        body_style = ParagraphStyle(
            "BodySmall",
            parent=base_styles["BodyText"],
            fontSize=8,
            leading=10.5,
            textColor=colors.HexColor("#1e293b")
        )
        body_bold = ParagraphStyle(
            "BodySmallBold",
            parent=body_style,
            fontName="Helvetica-Bold"
        )
        mono_style = ParagraphStyle(
            "MonoHash",
            fontName="Courier",
            fontSize=6.5,
            leading=8,
            textColor=colors.HexColor("#0f172a"),
            wordWrap="CJK"
        )
        disclaimer_style = ParagraphStyle(
            "Disclaimer",
            fontName="Helvetica-Oblique",
            fontSize=7.5,
            leading=9.5,
            textColor=colors.HexColor("#475569")
        )
        draft_style = ParagraphStyle(
            "DraftBanner",
            fontName="Helvetica-Bold",
            fontSize=12,
            leading=14,
            textColor=colors.HexColor("#b91c1c"),
            alignment=1
        )

        story = []
        selected_sections = set(report_data.get("selected_sections") or [])
        report_type = report_data.get("report_type", "Comprehensive Forensic Report")

        # ============================================================
        # COVER / HEADER
        # ============================================================
        if is_draft:
            story.append(Paragraph("*** DRAFT - PREVIEW ONLY - NOT FINALIZED ***", draft_style))
            story.append(Spacer(1, 6))

        story.append(Paragraph(cls._safe_text(report_type.upper()), title_style))
        story.append(Spacer(1, 4))
        story.append(Paragraph("ePRA Digital Evidence Management System", ParagraphStyle("SubHeader", parent=body_style, fontSize=9, textColor=colors.HexColor("#475569"))))
        story.append(Spacer(1, 6))
        story.append(HRFlowable(width="100%", thickness=2, color=colors.HexColor("#1e3a8a"), spaceAfter=10))

        # Case Meta Box
        crime_display = report_data.get("crime_type") or "Not Specified"
        dept_display = report_data.get("department") or "Not Specified"
        case_meta_data = [
            [
                Paragraph(f"<b>Case ID:</b> {cls._safe_text(case_id)}", body_style),
                Paragraph(f"<b>Report ID:</b> {cls._safe_text(report_id)}", body_style)
            ],
            [
                Paragraph(f"<b>Case Title:</b> {cls._safe_text(report_data.get('case_title') or case_id)}", body_style),
                Paragraph(f"<b>Crime Type:</b> {cls._safe_text(crime_display)}", body_style)
            ],
            [
                Paragraph(f"<b>Generated By:</b> {cls._safe_text(report_data.get('investigator_name') or 'Investigator')} ({cls._safe_text(report_data.get('investigator_role') or 'Investigator')})", body_style),
                Paragraph(f"<b>Generated At:</b> {cls._safe_text(report_data.get('generated_at'))}", body_style)
            ],
            [
                Paragraph(f"<b>Department:</b> {cls._safe_text(dept_display)}", body_style),
                Paragraph(f"<b>Report Scope:</b> {cls._safe_text(report_type)}", body_style)
            ]
        ]
        meta_table = Table(case_meta_data, colWidths=[270, 270])
        meta_table.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f8fafc")),
            ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#cbd5e1")),
            ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("RIGHTPADDING", (0, 0), (-1, -1), 8),
        ]))
        story.append(meta_table)
        story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: METADATA & INTEGRITY SUMMARY
        # ============================================================
        if "metadata_summary" in selected_sections:
            story.append(Paragraph("1. Forensic Evidence & Integrity Summary", h2_style))
            summary = report_data.get("evidence_summary", {})
            sum_data = [
                [
                    Paragraph("<b>Total Evidence Files</b>", body_style),
                    Paragraph(str(summary.get("total_evidence", 0)), body_bold),
                    Paragraph("<b>Verified Integrity (MATCH)</b>", body_style),
                    Paragraph(str(summary.get("integrity_verified", summary.get("integrity_match", 0))), body_bold)
                ],
                [
                    Paragraph("<b>Total Size</b>", body_style),
                    Paragraph(str(summary.get("total_size_formatted", "0 B")), body_style),
                    Paragraph("<b>Tampered / Modified (MISMATCH)</b>", body_style),
                    Paragraph(str(summary.get("integrity_tampered", summary.get("integrity_mismatch", 0))), body_bold)
                ],
                [
                    Paragraph("<b>Distinct File Types</b>", body_style),
                    Paragraph(str(summary.get("distinct_file_types", len(summary.get("types", {})))), body_style),
                    Paragraph("<b>Pending / Unchecked Verification</b>", body_style),
                    Paragraph(str(summary.get("integrity_pending", summary.get("integrity_not_verified", 0))), body_style)
                ],
                [
                    Paragraph("<b>Latest Evidence Upload</b>", body_style),
                    Paragraph(str(summary.get("latest_upload", "None")), body_style),
                    Paragraph("<b>Unknown / Error Outcome</b>", body_style),
                    Paragraph(str(summary.get("integrity_unknown", summary.get("integrity_error", 0))), body_style)
                ]
            ]
            sum_table = Table(sum_data, colWidths=[150, 120, 170, 100])
            sum_table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, -1), colors.HexColor("#f1f5f9")),
                ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#94a3b8")),
                ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#cbd5e1")),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ]))
            story.append(sum_table)
            story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: EVIDENCE DETAILS
        # ============================================================
        if "evidence_details" in selected_sections:
            story.append(Paragraph("2. Evidence Items & File Details", h2_style))
            ev_list = report_data.get("evidence_records", [])

            if not ev_list:
                story.append(Paragraph("<i>No evidence records recorded for this case.</i>", disclaimer_style))
            else:
                headers = ["#", "ID", "Filename", "Type", "Size", "Upload Date", "Hash Status"]
                table_rows = [[Paragraph(f"<b>{h}</b>", body_bold) for h in headers]]

                for idx, ev in enumerate(ev_list, start=1):
                    ev_id = ev.get("evidence_id") or str(idx)
                    fname = ev.get("original_filename", "unknown")
                    ftype = ev.get("file_type", "FILE")
                    fsize = ev.get("file_size_formatted") or f"{ev.get('file_size_bytes', 0):,} B"
                    up_date = ev.get("uploaded_at", "N/A")
                    if up_date and len(up_date) > 16:
                        up_date = up_date[:16].replace("T", " ")
                    h_status = ev.get("verification_status") or ev.get("integrity_status") or "Unknown"

                    table_rows.append([
                        Paragraph(str(idx), body_style),
                        Paragraph(cls._safe_text(ev_id), body_style),
                        Paragraph(cls._safe_text(fname), body_style),
                        Paragraph(cls._safe_text(ftype), body_style),
                        Paragraph(cls._safe_text(fsize), body_style),
                        Paragraph(cls._safe_text(up_date), body_style),
                        Paragraph(cls._safe_text(h_status), body_bold)
                    ])

                ev_table = Table(table_rows, colWidths=[20, 50, 160, 90, 60, 80, 80])
                ev_table.setStyle(TableStyle([
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                    ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#94a3b8")),
                    ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]))
                story.append(ev_table)
            story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: HASH VERIFICATION RESULTS (Passed through from backend)
        # ============================================================
        if "hash_verification" in selected_sections:
            story.append(Paragraph("3. Cryptographic Hash & Verification Audit", h2_style))
            story.append(Paragraph(
                "<i>Note: Cryptographic hashes and integrity verification outcomes are supplied by the "
                "authoritative integrated backend. Member 5 displays these verification results without local recalculation.</i>",
                disclaimer_style
            ))
            story.append(Spacer(1, 4))

            ev_list = report_data.get("evidence_records", [])
            headers = ["Evidence ID", "Original SHA-256 Digest", "Current SHA-256", "Backend Outcome", "Verified At"]
            hash_rows = [[Paragraph(f"<b>{h}</b>", body_bold) for h in headers]]

            for ev in ev_list:
                ev_id = ev.get("evidence_id", "N/A")
                orig_h = ev.get("original_sha256") or ev.get("baseline_hash") or "Not recorded"
                curr_h = ev.get("current_sha256") or ev.get("current_hash") or "N/A"
                v_status = ev.get("verification_status") or ev.get("integrity_status") or "Unknown"
                v_time = ev.get("verification_timestamp") or ev.get("verification_time") or "N/A"
                if v_time and len(v_time) > 16:
                    v_time = v_time[:16].replace("T", " ")

                hash_rows.append([
                    Paragraph(cls._safe_text(ev_id), body_style),
                    Paragraph(cls._safe_text(orig_h), mono_style),
                    Paragraph(cls._safe_text(curr_h), mono_style),
                    Paragraph(cls._safe_text(v_status), body_bold),
                    Paragraph(cls._safe_text(v_time), body_style)
                ])

            hash_table = Table(hash_rows, colWidths=[65, 185, 150, 70, 70])
            hash_table.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#94a3b8")),
                ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
                ("TOPPADDING", (0, 0), (-1, -1), 3),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
            ]))
            story.append(hash_table)
            story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: CHAIN OF CUSTODY LOGS
        # ============================================================
        if "chain_of_custody" in selected_sections:
            story.append(Paragraph("4. Chain of Custody Audit Trail", h2_style))
            c_logs = report_data.get("custody", [])

            if not c_logs:
                story.append(Paragraph("<i>No chain of custody logs recorded for this case.</i>", disclaimer_style))
            else:
                c_headers = ["Event ID", "Ev ID", "Action / Title", "Actor & Role", "Timestamp", "Outcome", "Remarks"]
                c_rows = [[Paragraph(f"<b>{h}</b>", body_bold) for h in c_headers]]

                for c in c_logs:
                    ev_id = str(c.get("evidence_id") or "Case")
                    eid = str(c.get("event_id") or c.get("id") or "-")
                    title = c.get("title") or c.get("action", "ACTION")
                    actor_desc = f"{c.get('actor_name') or c.get('investigator_name') or 'Investigator'}"
                    if c.get("actor_role"):
                        actor_desc += f" ({c.get('actor_role')})"
                    ts = c.get("timestamp", "N/A")
                    if ts and len(ts) > 16:
                        ts = ts[:16].replace("T", " ")
                    res = c.get("result") or c.get("outcome") or "SUCCESS"
                    remarks = c.get("remarks") or c.get("description") or "None"

                    c_rows.append([
                        Paragraph(cls._safe_text(eid), body_style),
                        Paragraph(cls._safe_text(ev_id), body_style),
                        Paragraph(cls._safe_text(title), body_style),
                        Paragraph(cls._safe_text(actor_desc), body_style),
                        Paragraph(cls._safe_text(ts), body_style),
                        Paragraph(cls._safe_text(res), body_bold),
                        Paragraph(cls._safe_text(remarks), body_style)
                    ])

                c_table = Table(c_rows, colWidths=[40, 45, 100, 110, 75, 50, 120])
                c_table.setStyle(TableStyle([
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                    ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#94a3b8")),
                    ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]))
                story.append(c_table)
            story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: TIMELINE RECONSTRUCTION
        # ============================================================
        if "timeline" in selected_sections:
            story.append(Paragraph("5. Investigation Timeline Reconstruction", h2_style))
            timeline_steps = report_data.get("timeline", [])

            if not timeline_steps:
                story.append(Paragraph("<i>No timeline events recorded.</i>", disclaimer_style))
            else:
                t_headers = ["Step", "Timestamp", "Event Title", "Actor", "Outcome", "Details"]
                t_rows = [[Paragraph(f"<b>{h}</b>", body_bold) for h in t_headers]]

                for step in timeline_steps:
                    st_num = str(step.get("step", "-"))
                    ts = step.get("timestamp_formatted") or step.get("timestamp", "N/A")
                    if ts and len(ts) > 16 and "T" in ts:
                        ts = ts[:16].replace("T", " ")
                    title = step.get("event_type", "Event").replace("_", " ").title()
                    actor = step.get("actor", "Unknown")
                    outcome = step.get("result", "SUCCESS")
                    det = step.get("description") or step.get("details", "")

                    t_rows.append([
                        Paragraph(cls._safe_text(st_num), body_style),
                        Paragraph(cls._safe_text(ts), body_style),
                        Paragraph(cls._safe_text(title), body_style),
                        Paragraph(cls._safe_text(actor), body_style),
                        Paragraph(cls._safe_text(outcome), body_bold),
                        Paragraph(cls._safe_text(det), body_style)
                    ])

                t_table = Table(t_rows, colWidths=[30, 85, 110, 85, 60, 170])
                t_table.setStyle(TableStyle([
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                    ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#94a3b8")),
                    ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]))
                story.append(t_table)
            story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: SUSPECT SUMMARY
        # ============================================================
        if "suspect_summary" in selected_sections:
            story.append(Paragraph("6. Suspect Summary", h2_style))
            suspects = report_data.get("suspect_records", [])

            if not suspects:
                story.append(Paragraph(
                    "<i>No suspect records supplied for this case (Integration Pending / No Data Available). "
                    "In digital forensics, persons of interest are never labeled guilty without legal adjudication.</i>",
                    disclaimer_style
                ))
            else:
                s_headers = ["Suspect ID", "Name", "Role / Relation", "Ranking", "Linked Evidence", "Notes"]
                s_rows = [[Paragraph(f"<b>{h}</b>", body_bold) for h in s_headers]]

                for s in suspects:
                    sid = s.get("suspect_id", "N/A")
                    name = s.get("name") or s.get("suspect_name", "Unknown")
                    role = s.get("role_or_relation") or s.get("entity_type", "Person of Interest")
                    rank = str(s.get("externally_supplied_ranking") or s.get("rank") or "Unranked")
                    linked = ", ".join([str(x) for x in s.get("linked_evidence_ids", [])]) or "None"
                    notes = s.get("notes", "")

                    s_rows.append([
                        Paragraph(cls._safe_text(sid), body_style),
                        Paragraph(cls._safe_text(name), body_bold),
                        Paragraph(cls._safe_text(role), body_style),
                        Paragraph(cls._safe_text(rank), body_style),
                        Paragraph(cls._safe_text(linked), body_style),
                        Paragraph(cls._safe_text(notes), body_style)
                    ])

                s_table = Table(s_rows, colWidths=[60, 110, 90, 50, 80, 150])
                s_table.setStyle(TableStyle([
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                    ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#94a3b8")),
                    ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]))
                story.append(s_table)
            story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: EPRA ANALYSIS RESULTS
        # ============================================================
        if "epra_analysis" in selected_sections:
            story.append(Paragraph("7. EPRA Prioritization Analysis Results", h2_style))
            epra_results = report_data.get("epra_analysis", [])

            if not epra_results:
                story.append(Paragraph(
                    "<i>EPRA AI Prioritization Analysis: Pending connection to downstream prioritization module. "
                    "No measured scores recorded.</i>",
                    disclaimer_style
                ))
            else:
                epra_headers = ["Evidence ID", "Priority Rank", "Score", "Status", "Provenance", "Notes"]
                epra_rows = [[Paragraph(f"<b>{h}</b>", body_bold) for h in epra_headers]]

                for res in epra_results:
                    ev_id = res.get("evidence_id", "N/A")
                    rank = str(res.get("priority_rank") or res.get("rank") or "N/A")
                    score = f"{res.get('priority_score', res.get('epra_score', 0)):.2f}" if (res.get("priority_score") is not None or res.get("epra_score") is not None) else "N/A"
                    status = res.get("status") or res.get("analysis_status", "PENDING")
                    prov = res.get("provenance_source") or "EPRA Model v2"
                    notes = res.get("notes") or res.get("missing_input_reason") or f"Priority: {res.get('priority', 'N/A')}"

                    epra_rows.append([
                        Paragraph(cls._safe_text(ev_id), body_style),
                        Paragraph(cls._safe_text(rank), body_bold),
                        Paragraph(cls._safe_text(score), body_style),
                        Paragraph(cls._safe_text(status), body_style),
                        Paragraph(cls._safe_text(prov), body_style),
                        Paragraph(cls._safe_text(notes), body_style)
                    ])

                epra_table = Table(epra_rows, colWidths=[70, 70, 60, 70, 100, 170])
                epra_table.setStyle(TableStyle([
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                    ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#94a3b8")),
                    ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]))
                story.append(epra_table)
            story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: INVESTIGATOR ACTIVITY LOGS
        # ============================================================
        if "activity_logs" in selected_sections:
            story.append(Paragraph("8. Investigator Activity Audit Trail", h2_style))
            act_logs = report_data.get("activity", [])

            if not act_logs:
                story.append(Paragraph("<i>No investigator activity logs recorded.</i>", disclaimer_style))
            else:
                a_headers = ["Investigator", "Action / Activity", "Outcome", "Timestamp", "Details"]
                a_rows = [[Paragraph(f"<b>{h}</b>", body_bold) for h in a_headers]]

                for a in act_logs:
                    inv = a.get("investigator") or a.get("investigator_name", "Unknown")
                    act = a.get("activity") or a.get("action", "")
                    outcome = a.get("outcome", "SUCCESS")
                    t_val = a.get("time") or a.get("timestamp", "N/A")
                    if t_val and len(t_val) > 16:
                        t_val = t_val[:16].replace("T", " ")
                    det = a.get("details", "")

                    a_rows.append([
                        Paragraph(cls._safe_text(inv), body_style),
                        Paragraph(cls._safe_text(act), body_style),
                        Paragraph(cls._safe_text(outcome), body_bold),
                        Paragraph(cls._safe_text(t_val), body_style),
                        Paragraph(cls._safe_text(det), body_style)
                    ])

                a_table = Table(a_rows, colWidths=[110, 110, 60, 80, 180])
                a_table.setStyle(TableStyle([
                    ("BACKGROUND", (0, 0), (-1, 0), colors.HexColor("#e2e8f0")),
                    ("BOX", (0, 0), (-1, -1), 0.5, colors.HexColor("#94a3b8")),
                    ("INNERGRID", (0, 0), (-1, -1), 0.5, colors.HexColor("#e2e8f0")),
                    ("TOPPADDING", (0, 0), (-1, -1), 3),
                    ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
                ]))
                story.append(a_table)
            story.append(Spacer(1, 10))

        # ============================================================
        # SECTION: CONCLUSIONS & RECOMMENDATIONS
        # ============================================================
        if "conclusions" in selected_sections:
            story.append(Paragraph("9. Conclusions & Recommendations", h2_style))
            conclusions = report_data.get("conclusions_text")
            recommendations = report_data.get("recommendations_text")

            if not conclusions and not recommendations:
                story.append(Paragraph(
                    "<i>No formal conclusions or recommendations supplied by investigator.</i>",
                    disclaimer_style
                ))
            else:
                if conclusions:
                    story.append(Paragraph("<b>Forensic Findings & Conclusions:</b>", body_bold))
                    story.append(Paragraph(cls._safe_text(conclusions), body_style))
                    story.append(Spacer(1, 6))
                if recommendations:
                    story.append(Paragraph("<b>Investigative Recommendations:</b>", body_bold))
                    story.append(Paragraph(cls._safe_text(recommendations), body_style))
                    story.append(Spacer(1, 6))

                author = report_data.get("investigator_name", "Investigator")
                story.append(Paragraph(
                    f"<i>Documented by: {cls._safe_text(author)} on {cls._safe_text(report_data.get('generated_at'))}</i>",
                    disclaimer_style
                ))
            story.append(Spacer(1, 10))

        # Build document
        doc.build(story, canvasmaker=NumberedCanvas)
        return str(filename)
