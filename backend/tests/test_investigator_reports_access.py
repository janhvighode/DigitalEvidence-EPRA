"""
Integration & Unit Test Suite for Investigator Reports Access.
Verifies:
1. Assigned Investigator (role_id == 2) can access GET /cases/{case_id}/reports/summary
2. Summary includes enriched metrics: total_reports, latest_report_name, latest_generated_at
3. Assigned Investigator can access GET /cases/{case_id}/reports/history
4. History pagination and metadata verification
5. Assigned Investigator can access GET /cases/{case_id}/reports/preview/{report_id}
6. Assigned Investigator can access GET /cases/{case_id}/reports/download/{report_id}
7. Non-assigned Investigator is blocked with 403 Forbidden
8. Non-existent case returns 404 Not Found
9. Non-existent report returns 404 Not Found
10. Cross-case report access is blocked with 404 Not Found
11. Investigator CANNOT generate reports via POST /cases/{case_id}/reports/generate (403 Forbidden)
12. Investigator CANNOT generate draft previews via POST /cases/{case_id}/reports/preview (403 Forbidden)
13. Both integer Case.id and string Case.case_id work identically
"""

import os
import sys
import unittest
import tempfile
from pathlib import Path
from datetime import datetime, timezone

# Add backend to sys.path
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException
from fastapi.responses import FileResponse

from database.database import Base
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.report_record import ReportRecord
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from routes.technical_report_routes import (
    verify_report_read_access,
    verify_cyber_expert_case_access,
    get_case_reporting_summary,
    get_report_history,
    preview_existing_report,
    download_report_by_id,
    generate_report,
    preview_report,
    DEFAULT_REPORTS_DIR
)
from schemas.technical_report import ReportRequest


def setup_in_memory_db():
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(
        bind=engine,
        tables=[
            Role.__table__,
            City.__table__,
            CyberCell.__table__,
            User.__table__,
            Case.__table__,
            Evidence.__table__,
            EvidenceHash.__table__,
            ReportRecord.__table__,
            CustodyLog.__table__,
            ActivityLog.__table__,
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Seed roles
    roles = [
        Role(id=1, role_name="Admin"),
        Role(id=2, role_name="Investigator"),
        Role(id=3, role_name="Cyber Expert"),
    ]
    city = City(id=1, city_name="Mumbai")
    cell = CyberCell(id=1, cyber_cell_name="Central Cyber Cell", admin_email="admin@cell.gov", city_id=1)
    db.add_all(roles)
    db.add_all([city, cell])
    db.commit()

    # Users
    inv1 = User(
        id=201,
        full_name="Investigator Sarah Connor",
        username="inv_sarah",
        email="sarah@police.gov",
        phone_number="9876543210",
        password="hashed_pwd",
        role_id=2,
        cyber_cell_id=1,
        is_active=True
    )
    inv2 = User(
        id=202,
        full_name="Investigator John Wick",
        username="inv_wick",
        email="wick@police.gov",
        phone_number="9876543211",
        password="hashed_pwd",
        role_id=2,
        cyber_cell_id=1,
        is_active=True
    )
    expert = User(
        id=301,
        full_name="Cyber Expert Alice Smith",
        username="expert_alice",
        email="alice@lab.gov",
        phone_number="9876543212",
        password="hashed_pwd",
        role_id=3,
        cyber_cell_id=1,
        is_active=True
    )
    admin = User(
        id=101,
        full_name="Admin Chief",
        username="admin_chief",
        email="chief@hq.gov",
        phone_number="9876543213",
        password="hashed_pwd",
        role_id=1,
        cyber_cell_id=1,
        is_active=True
    )
    db.add_all([inv1, inv2, expert, admin])
    db.commit()

    # Cases
    case1 = Case(
        id=1,
        case_id="CASE-2026-001",
        title="Operation Cyber Fortress",
        description="High-profile intrusion case",
        investigator_id=201,  # inv1 assigned
        cyber_expert_id=301,  # expert assigned
        priority="High",
        status="In Progress"
    )
    case2 = Case(
        id=2,
        case_id="CASE-2026-002",
        title="Operation Darknet",
        description="Unrelated case",
        investigator_id=202,  # inv2 assigned
        cyber_expert_id=301,
        priority="Medium",
        status="Open"
    )
    db.add_all([case1, case2])
    db.commit()

    # Evidence for Case 1
    ev1 = Evidence(
        id=101,
        case_id=1,
        evidence_id="EV-101",
        file_name="ram_dump.raw",
        file_path="uploads/cases/1/ram_dump.raw",
        file_type="Memory Dump",
        file_size=4194304,
        status="Active"
    )
    ev2 = Evidence(
        id=102,
        case_id=1,
        evidence_id="EV-102",
        file_name="network_pcap.pcap",
        file_path="uploads/cases/1/network_pcap.pcap",
        file_type="PCAP",
        file_size=2097152,
        status="Active"
    )
    db.add_all([ev1, ev2])
    db.commit()

    # Hash records for integrity summary
    h1 = EvidenceHash(
        id=101,
        evidence_id=101,
        file_name="ram_dump.raw",
        sha256_hash="1111222233334444555566667777888899990000aaaabbbbccccddddeeeeffff",
        current_hash="1111222233334444555566667777888899990000aaaabbbbccccddddeeeeffff",
        hash_match=True,
        tampered=False,
        integrity_status="MATCH",
        verified_at=datetime(2026, 9, 10, 10, 0, 0, tzinfo=timezone.utc),
        verified_by=301
    )
    h2 = EvidenceHash(
        id=102,
        evidence_id=102,
        file_name="network_pcap.pcap",
        sha256_hash="222233334444555566667777888899990000aaaabbbbccccddddeeeeffff1111",
        current_hash="222233334444555566667777888899990000aaaabbbbccccddddeeeeffff1111",
        hash_match=True,
        tampered=False,
        integrity_status="MATCH",
        verified_at=datetime(2026, 9, 10, 11, 0, 0, tzinfo=timezone.utc),
        verified_by=301
    )
    db.add_all([h1, h2])
    db.commit()

    return db, inv1, inv2, expert, admin, case1, case2


class TestInvestigatorReportsAccess(unittest.TestCase):

    def setUp(self):
        self.db, self.inv1, self.inv2, self.expert, self.admin, self.case1, self.case2 = setup_in_memory_db()
        
        # Ensure default reports directory exists for file tests
        DEFAULT_REPORTS_DIR.mkdir(parents=True, exist_ok=True)
        
        # Create an actual physical test report file in DEFAULT_REPORTS_DIR
        self.test_pdf = DEFAULT_REPORTS_DIR / "test_report_c1.pdf"
        self.test_pdf.write_bytes(b"%PDF-1.4 Mock forensic report binary content")
        
        # Insert ReportRecord for Case 1
        self.rep1 = ReportRecord(
            id="5001",
            case_id="1",
            case_title="Operation Cyber Fortress",
            investigator_name="Investigator Sarah Connor",
            file_name="Technical_Report_CASE-2026-001_v1.pdf",
            report_type="FORENSIC_SUMMARY",
            file_format="PDF",
            file_path=str(self.test_pdf),
            file_size_bytes=len(b"%PDF-1.4 Mock forensic report binary content"),
            generated_by_id=str(self.expert.id),
            generated_by_role="Cyber Expert",
            is_draft=False,
            generated_at=datetime(2026, 9, 11, 14, 30, 0, tzinfo=timezone.utc)
        )
        
        # Insert ReportRecord for Case 2 (cross-case test)
        self.rep2 = ReportRecord(
            id="5002",
            case_id="2",
            case_title="Operation Darknet",
            investigator_name="Investigator John Wick",
            file_name="Technical_Report_CASE-2026-002_v1.pdf",
            report_type="FULL_AUDIT",
            file_format="PDF",
            file_path=str(self.test_pdf),
            file_size_bytes=1024,
            generated_by_id=str(self.expert.id),
            generated_by_role="Cyber Expert",
            is_draft=False,
            generated_at=datetime(2026, 9, 12, 10, 0, 0, tzinfo=timezone.utc)
        )
        self.db.add_all([self.rep1, self.rep2])
        self.db.commit()

    def tearDown(self):
        self.db.close()
        if self.test_pdf.exists():
            try:
                self.test_pdf.unlink()
            except Exception:
                pass

    def test_01_verify_report_read_access_assigned_investigator(self):
        """Assigned investigator (role_id=2) can access report read endpoints."""
        case = verify_report_read_access(self.case1.id, self.inv1, self.db)
        self.assertEqual(case.id, self.case1.id)
        
        # By string case_id
        case_by_str = verify_report_read_access(self.case1.case_id, self.inv1, self.db)
        self.assertEqual(case_by_str.id, self.case1.id)

    def test_02_verify_report_read_access_unassigned_investigator_forbidden(self):
        """Unassigned investigator gets 403 Forbidden."""
        with self.assertRaises(HTTPException) as ctx:
            verify_report_read_access(self.case1.id, self.inv2, self.db)
        self.assertEqual(ctx.exception.status_code, 403)
        self.assertIn("not assigned as Investigator", ctx.exception.detail)

    def test_03_verify_report_read_access_unauthenticated_401(self):
        """Missing user raises 401 Unauthorized."""
        with self.assertRaises(HTTPException) as ctx:
            verify_report_read_access(self.case1.id, None, self.db)
        self.assertEqual(ctx.exception.status_code, 401)

    def test_04_verify_report_read_access_nonexistent_case_404(self):
        """Non-existent case ID raises 404 Not Found."""
        with self.assertRaises(HTTPException) as ctx:
            verify_report_read_access("999999", self.inv1, self.db)
        self.assertEqual(ctx.exception.status_code, 404)

    def test_05_investigator_reporting_summary(self):
        """Assigned investigator can retrieve case reporting summary with enriched metrics."""
        summary = get_case_reporting_summary(str(self.case1.id), db=self.db, current_user=self.inv1)
        tot = summary["total_evidence"] if isinstance(summary, dict) else summary.total_evidence
        ver = summary["verified_evidence"] if isinstance(summary, dict) else summary.verified_evidence
        tamp = summary["tampered_evidence"] if isinstance(summary, dict) else summary.tampered_evidence
        pend = summary.get("pending_evidence", summary.get("pending_verification", 0)) if isinstance(summary, dict) else getattr(summary, "pending_evidence", getattr(summary, "pending_verification", 0))
        tot_rep = summary["total_reports"] if isinstance(summary, dict) else summary.total_reports
        latest_name = summary["latest_report_name"] if isinstance(summary, dict) else summary.latest_report_name
        latest_gen = summary["latest_generated_at"] if isinstance(summary, dict) else summary.latest_generated_at
        self.assertEqual(tot, 2)
        self.assertEqual(ver, 2)
        self.assertEqual(tamp, 0)
        self.assertEqual(pend, 0)
        self.assertEqual(tot_rep, 1)
        self.assertEqual(latest_name, "Technical_Report_CASE-2026-001_v1.pdf")
        self.assertIsNotNone(latest_gen)

    def test_06_investigator_reporting_summary_by_case_code(self):
        """Summary endpoint handles string case code like CASE-2026-001."""
        summary = get_case_reporting_summary("CASE-2026-001", db=self.db, current_user=self.inv1)
        cid = summary["case_id"] if isinstance(summary, dict) else summary.case_id
        tot = summary["total_evidence"] if isinstance(summary, dict) else summary.total_evidence
        tot_rep = summary["total_reports"] if isinstance(summary, dict) else summary.total_reports
        self.assertEqual(cid, "CASE-2026-001")
        self.assertEqual(tot, 2)
        self.assertEqual(tot_rep, 1)

    def test_07_unassigned_investigator_cannot_view_summary(self):
        """Unassigned investigator calling get_case_reporting_summary gets 403."""
        with self.assertRaises(HTTPException) as ctx:
            get_case_reporting_summary(str(self.case1.id), db=self.db, current_user=self.inv2)
        self.assertEqual(ctx.exception.status_code, 403)

    def test_08_investigator_report_history(self):
        """Assigned investigator can retrieve report history with pagination."""
        history = get_report_history(str(self.case1.id), page=1, page_size=10, db=self.db, current_user=self.inv1)
        tot_rep = history["total_reports"] if isinstance(history, dict) else history.total_reports
        reports = history.get("reports", history.get("items", [])) if isinstance(history, dict) else getattr(history, "reports", getattr(history, "items", []))
        self.assertEqual(tot_rep, 1)
        self.assertEqual(len(reports), 1)
        item = reports[0]
        rep_id = item["report_id"] if isinstance(item, dict) else item.report_id
        rep_name = item["report_name"] if isinstance(item, dict) else item.report_name
        rep_type = item["report_type"] if isinstance(item, dict) else item.report_type
        fmt = item["file_format"] if isinstance(item, dict) else item.file_format
        dl_url = item["download_url"] if isinstance(item, dict) else item.download_url
        prev_url = item["preview_url"] if isinstance(item, dict) else item.preview_url
        self.assertEqual(rep_id, "5001")
        self.assertEqual(rep_name, "Technical_Report_CASE-2026-001_v1.pdf")
        self.assertEqual(rep_type, "FORENSIC_SUMMARY")
        self.assertEqual(fmt, "PDF")
        self.assertIn("/download/5001", dl_url)
        self.assertIn("/preview/5001", prev_url)

    def test_09_unassigned_investigator_cannot_view_history(self):
        """Unassigned investigator calling get_report_history gets 403."""
        with self.assertRaises(HTTPException) as ctx:
            get_report_history(str(self.case1.id), page=1, page_size=10, db=self.db, current_user=self.inv2)
        self.assertEqual(ctx.exception.status_code, 403)

    def test_10_investigator_preview_existing_report(self):
        """Assigned investigator can preview an existing report file."""
        response = preview_existing_report(str(self.case1.id), "5001", db=self.db, current_user=self.inv1)
        self.assertIsInstance(response, FileResponse)
        self.assertEqual(response.filename, "test_report_c1.pdf")
        self.assertEqual(response.media_type, "application/pdf")

    def test_11_preview_cross_case_isolation_404(self):
        """Investigator for Case 1 attempting to preview Case 2 report gets 404."""
        with self.assertRaises(HTTPException) as ctx:
            preview_existing_report(str(self.case1.id), "5002", db=self.db, current_user=self.inv1)
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertIn("does not belong to Case", ctx.exception.detail)

    def test_12_preview_nonexistent_report_404(self):
        """Non-existent report ID returns 404."""
        with self.assertRaises(HTTPException) as ctx:
            preview_existing_report(str(self.case1.id), "9999", db=self.db, current_user=self.inv1)
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertIn("not found", ctx.exception.detail)

    def test_13_preview_missing_file_on_disk_404(self):
        """ReportRecord exists in DB but file missing on disk returns 404."""
        missing_rep = ReportRecord(
            id="5003",
            case_id="1",
            case_title="Operation Cyber Fortress",
            investigator_name="Investigator Sarah Connor",
            file_name="Missing_Report.pdf",
            report_type="FORENSIC_SUMMARY",
            file_format="PDF",
            file_path=str(DEFAULT_REPORTS_DIR / "non_existent_file_xyz.pdf"),
            file_size_bytes=100,
            generated_by_id=str(self.expert.id),
            generated_by_role="Cyber Expert",
            is_draft=False,
            generated_at=datetime.now(timezone.utc)
        )
        self.db.add(missing_rep)
        self.db.commit()

        with self.assertRaises(HTTPException) as ctx:
            preview_existing_report(str(self.case1.id), "5003", db=self.db, current_user=self.inv1)
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertIn("not found on disk", ctx.exception.detail)

    def test_14_investigator_download_report(self):
        """Assigned investigator can download a report file."""
        response = download_report_by_id(str(self.case1.id), "5001", db=self.db, current_user=self.inv1)
        self.assertIsInstance(response, FileResponse)
        self.assertEqual(response.filename, "test_report_c1.pdf")
        self.assertEqual(response.media_type, "application/pdf")

    def test_15_download_cross_case_isolation_404(self):
        """Downloading a report belonging to another case yields 404."""
        with self.assertRaises(HTTPException) as ctx:
            download_report_by_id(str(self.case1.id), "5002", db=self.db, current_user=self.inv1)
        self.assertEqual(ctx.exception.status_code, 404)
        self.assertIn("does not belong to Case", ctx.exception.detail)

    def test_16_investigator_cannot_generate_report_403(self):
        """Investigator (role_id=2) CANNOT call generate_report (restricted to Cyber Expert role_id=3)."""
        req = ReportRequest(case_id=str(self.case1.id))
        with self.assertRaises(HTTPException) as ctx:
            generate_report(str(self.case1.id), payload=req, db=self.db, current_user=self.inv1)
        self.assertEqual(ctx.exception.status_code, 403)
        self.assertIn("Cyber Expert", ctx.exception.detail)

    def test_17_investigator_cannot_draft_preview_report_403(self):
        """Investigator (role_id=2) CANNOT call preview_report (draft generator restricted to role_id=3)."""
        req = ReportRequest(case_id=str(self.case1.id))
        with self.assertRaises(HTTPException) as ctx:
            preview_report(str(self.case1.id), report=req, db=self.db, current_user=self.inv1)
        self.assertEqual(ctx.exception.status_code, 403)
        self.assertIn("Cyber Expert", ctx.exception.detail)

    def test_18_expert_authorization_intact(self):
        """Assigned Cyber Expert still retains both read access and generate access."""
        # Read access
        summary = get_case_reporting_summary(str(self.case1.id), db=self.db, current_user=self.expert)
        tot_rep = summary["total_reports"] if isinstance(summary, dict) else summary.total_reports
        self.assertEqual(tot_rep, 1)

        # Verification check passes for expert
        case = verify_cyber_expert_case_access(self.case1.id, self.expert, self.db)
        self.assertEqual(case.id, self.case1.id)


if __name__ == "__main__":
    unittest.main()
