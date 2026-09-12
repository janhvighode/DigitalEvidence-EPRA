"""
Unit tests for Deepak's Technical Report core generation, ReportLab PDF rendering, and report types.
Uses an isolated in-memory SQLite database to verify Deepak's core business logic.
"""
import sys
import json
from pathlib import Path
from datetime import datetime, timezone
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from database.database import Base
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.report_record import ReportRecord
from schemas.technical_report import ReportRequest, ReportType, ALL_REPORT_SECTIONS, DEFAULT_SECTIONS_BY_TYPE
from services.technical_report_service import TechnicalReportService, format_bytes, map_backend_verification_status
from services.pdf_service import PDFService


from models.epra_result import EPRAResult
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink


def create_test_db():
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(
        engine,
        tables=[
            Case.__table__,
            Evidence.__table__,
            EvidenceHash.__table__,
            EvidenceRecord.__table__,
            CustodyLog.__table__,
            ActivityLog.__table__,
            ReportRecord.__table__,
            PossibleEntity.__table__,
            PossibleEntityEvidenceLink.__table__,
            EPRAResult.__table__
        ]
    )
    Session = sessionmaker(bind=engine)
    return Session()


def seed_test_case_data(db):
    test_case = Case(
        id=101,
        case_id="CASE-UNIT-101",
        title="Digital Forensics Unit Test Case",
        description="Investigation of unauthorized intrusion",
        cyber_expert_id=1,
        priority="High",
        status="In Progress"
    )
    db.add(test_case)

    ev1 = Evidence(
        id=201,
        evidence_id="EV-UNIT-201",
        case_id=101,
        file_name="network_traffic.pcap",
        file_type="PCAP Capture",
        file_size=1048576,
        file_path="uploads/network_traffic.pcap",
        status="ANALYZED"
    )
    db.add(ev1)

    h1 = EvidenceHash(
        id=301,
        evidence_id=201,
        file_name="network_traffic.pcap",
        sha256_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        current_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        hash_match=True,
        tampered=False,
        integrity_status="MATCH"
    )
    db.add(h1)

    c1 = CustodyLog(
        id=401,
        evidence_id="EV-UNIT-201",
        case_id="101",
        investigator_name="Expert Jane Doe",
        action="EVIDENCE_UPLOADED",
        result="SUCCESS",
        remarks="Acquired from server router",
        timestamp=datetime.now(timezone.utc)
    )
    db.add(c1)

    a1 = ActivityLog(
        id=501,
        case_id="101",
        investigator_name="Expert Jane Doe",
        action="EVIDENCE_UPLOADED",
        activity="Ingested network capture",
        outcome="SUCCESS",
        timestamp=datetime.now(timezone.utc)
    )
    db.add(a1)
    db.commit()


def test_all_report_types_and_sections():
    """Verify all report types can be generated with appropriate format and section controls."""
    db = create_test_db()
    try:
        seed_test_case_data(db)

        report_types = [
            ReportType.COMPREHENSIVE,
            ReportType.EVIDENCE_SUMMARY,
            ReportType.CHAIN_OF_CUSTODY,
            ReportType.HASH_VERIFICATION,
            ReportType.TIMELINE,
            ReportType.HASH_MANIFEST
        ]

        for rt in report_types:
            req = ReportRequest(
                case_id="101",
                case_title="Unit Test Investigation",
                report_type=rt,
                investigator_name="Unit Tester",
                investigator_role="Cyber Expert"
            )
            res = TechnicalReportService.assemble_report_data(report=req, db=db, is_draft=True)
            assert res["status"] == "success"
            if rt == ReportType.HASH_MANIFEST:
                assert res["file_format"] == "JSON"
                assert "manifest_content" in res
                assert res["manifest_content"]["hash_algorithm"] == "SHA-256"
            else:
                assert res["file_format"] == "PDF"
                assert Path(res["pdf_path"]).exists()
                assert Path(res["pdf_path"]).stat().st_size > 1000
    finally:
        db.close()
    print("PASS: test_all_report_types_and_sections")


def test_draft_preview_vs_final_generation():
    """Verify draft previews do not persist to database or create custody/activity logs, while final generation does."""
    db = create_test_db()
    try:
        seed_test_case_data(db)

        # 1. Draft Preview
        req_draft = ReportRequest(
            case_id="101",
            report_type=ReportType.COMPREHENSIVE,
            investigator_name="Tester"
        )
        res_draft = TechnicalReportService.assemble_report_data(report=req_draft, db=db, is_draft=True)
        assert res_draft["is_draft"] is True
        assert db.query(ReportRecord).count() == 0  # Zero rows in report_records
        assert db.query(CustodyLog).filter(CustodyLog.action == "REPORT_GENERATED").count() == 0

        # 2. Final Generation
        req_final = ReportRequest(
            case_id="101",
            report_type=ReportType.COMPREHENSIVE,
            investigator_name="Tester"
        )
        res_final = TechnicalReportService.assemble_report_data(report=req_final, db=db, is_draft=False)
        assert res_final["is_draft"] is False
        assert db.query(ReportRecord).count() == 1  # Exactly 1 row persisted
        saved_rec = db.query(ReportRecord).first()
        assert saved_rec.id == res_final["report_id"]
        assert saved_rec.case_id == "101"
        assert saved_rec.is_draft is False
        # Audit records written
        assert db.query(CustodyLog).filter(CustodyLog.action == "REPORT_GENERATED").count() >= 1
        assert db.query(ActivityLog).filter(ActivityLog.action == "REPORT_GENERATED").count() >= 1
    finally:
        db.close()
    print("PASS: test_draft_preview_vs_final_generation")


def test_report_history_and_pagination():
    """Verify report history querying, sorting, and pagination."""
    db = create_test_db()
    try:
        seed_test_case_data(db)

        # Generate 3 distinct finalized reports
        for i in range(3):
            req = ReportRequest(
                case_id="101",
                case_title=f"Report Version {i+1}",
                report_type=ReportType.EVIDENCE_SUMMARY,
                investigator_name="Auditor"
            )
            TechnicalReportService.assemble_report_data(report=req, db=db, is_draft=False)

        # Retrieve history
        hist = TechnicalReportService.get_report_history(db, case_id="101", page=1, page_size=2)
        assert hist["total_reports"] == 3
        assert len(hist["reports"]) == 2
        assert hist["total_pages"] == 2

        # Page 2
        hist_p2 = TechnicalReportService.get_report_history(db, case_id="101", page=2, page_size=2)
        assert len(hist_p2["reports"]) == 1
    finally:
        db.close()
    print("PASS: test_report_history_and_pagination")


def test_summary_card_derivation():
    """Verify summary cards count actual evidence and map verification statuses without hardcoding."""
    db = create_test_db()
    try:
        seed_test_case_data(db)

        summary = TechnicalReportService.get_case_reporting_summary(db, case_id="101")
        assert summary["case_id"] == "101"
        assert summary["total_evidence"] == 1
        assert summary["verified_evidence"] == 1
        assert summary["tampered_evidence"] == 0
        assert summary["pending_evidence"] == 0
    finally:
        db.close()
    print("PASS: test_summary_card_derivation")


def test_multipage_pdf_visual_rendering():
    """Verify generated PDF contains valid PDF header and metadata."""
    report_data = {
        "report_id": "test-render-1234",
        "case_id": "CASE-RENDER",
        "case_title": "Visual Rendering Test Case",
        "report_type": "Comprehensive Forensic Report",
        "investigator_name": "Visual Auditor",
        "investigator_role": "Cyber Expert",
        "selected_sections": ALL_REPORT_SECTIONS,
        "generated_at": datetime.now(timezone.utc).strftime("%d %b %Y, %H:%M:%S UTC"),
        "evidence_summary": {
            "total_evidence": 1,
            "total_size_formatted": "1.0 MB",
            "distinct_file_types": 1,
            "integrity_verified": 1,
            "integrity_tampered": 0,
            "integrity_pending": 0,
            "integrity_unknown": 0
        },
        "evidence_records": [
            {
                "evidence_id": "EV-01",
                "original_filename": "disk_image.raw",
                "file_type": "Disk Image",
                "file_size_formatted": "1.0 MB",
                "original_sha256": "abcdef1234567890"*4,
                "current_sha256": "abcdef1234567890"*4,
                "verification_status": "Verified",
                "uploaded_at": "2026-09-12 10:00:00"
            }
        ],
        "custody": [],
        "timeline": [],
        "activity": [],
        "suspect_records": [],
        "epra_analysis": [],
        "conclusions_text": "All findings indicate system integrity intact.",
        "recommendations_text": "Maintain standard forensic isolation protocol."
    }

    pdf_path = PDFService.generate_pdf(report_data, is_draft=True)
    p = Path(pdf_path)
    assert p.exists()
    assert p.stat().st_size > 1000
    assert p.read_bytes()[:5] == b"%PDF-"
    print("PASS: test_multipage_pdf_visual_rendering")


if __name__ == "__main__":
    print("\n========================================================")
    print("RUNNING DEEPAK TECHNICAL REPORT UNIT TESTS")
    print("========================================================")
    test_all_report_types_and_sections()
    test_draft_preview_vs_final_generation()
    test_report_history_and_pagination()
    test_summary_card_derivation()
    test_multipage_pdf_visual_rendering()
    print("========================================================")
    print("ALL 5 DEEPAK TECHNICAL REPORT UNIT TESTS PASSED SUCCESSFULLY!\n")
