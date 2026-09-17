"""
Comprehensive Test Suite for Project-Wide Report Persistence, View, and Download Integration.
Verifies all 20 required acceptance criteria:
1. generate report creates DB record
2. generated PDF/file persists
3. DB record points to correct persisted file
4. View returns persisted report
5. View does not regenerate report
6. Download returns persisted report
7. Download returns application/pdf
8. downloaded PDF is valid/non-empty
9. report list/history comes from DB
10. authorized Cyber Expert works
11. authorized Investigator works
12. unauthorized user blocked
13. cross-case report access blocked
14. invalid report_id -> 404
15. DB record + missing file handled cleanly
16. no arbitrary frontend file path accepted
17. new dynamic case report works
18. separate request/session still retrieves report
19. existing Investigator report regression remains working
20. no hardcoded CASE-6922/report ID
"""

import sys
from uuid import uuid4
from pathlib import Path
from datetime import datetime, timezone
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient

backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from database.database import SessionLocal
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.report_record import ReportRecord
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog

from schemas.technical_report import ReportRequest, ReportType
from services.technical_report_service import TechnicalReportService
from services.report_service import (
    get_report_view_data,
    get_report_pdf_file_path,
    get_investigator_reports_table,
    get_investigator_reports_overview
)
from routes.report_routes import (
    download_report_by_path,
    download_report_alias,
    preview_report_inline,
    view_report_structured,
    generate_report_from_reports_module
)
from routes.technical_report_routes import (
    generate_report,
    view_case_report,
    download_report_by_id,
    preview_existing_report,
    get_report_history
)
from app.main import app

client = TestClient(app)


def cleanup_test_artifacts(db, case_identifiers, user_usernames):
    """Clean test artifacts safely."""
    try:
        cases = db.query(Case).filter(Case.case_id.in_(case_identifiers)).all()
        c_ids = [c.id for c in cases]
        c_str_ids = [c.case_id for c in cases] + [str(c.id) for c in cases]

        if c_str_ids:
            reps = db.query(ReportRecord).filter(ReportRecord.case_id.in_(c_str_ids)).all()
            for r in reps:
                if r.file_path and Path(r.file_path).exists():
                    try:
                        Path(r.file_path).unlink()
                    except Exception:
                        pass
                db.delete(r)

            db.query(CustodyLog).filter(CustodyLog.case_id.in_(c_str_ids)).delete(synchronize_session=False)
            db.query(ActivityLog).filter(ActivityLog.case_id.in_(c_str_ids)).delete(synchronize_session=False)

            evs = db.query(Evidence).filter(Evidence.case_id.in_(c_ids)).all()
            ev_ids = [e.id for e in evs]
            if ev_ids:
                db.query(EvidenceHash).filter(EvidenceHash.evidence_id.in_(ev_ids)).delete(synchronize_session=False)
                for ev in evs:
                    if ev.file_path and Path(ev.file_path).exists():
                        try:
                            Path(ev.file_path).unlink()
                        except Exception:
                            pass
                db.query(Evidence).filter(Evidence.id.in_(ev_ids)).delete(synchronize_session=False)

            db.query(Case).filter(Case.id.in_(c_ids)).delete(synchronize_session=False)
            db.commit()

        for uname in user_usernames:
            u = db.query(User).filter(User.username == uname).first()
            if u:
                db.delete(u)
        db.commit()
    except Exception as e:
        print(f"Cleanup error: {e}")
        db.rollback()


@pytest.fixture(scope="module")
def setup_environment():
    """Sets up test users, cases, and evidence records."""
    db = SessionLocal()
    case_codes = ["CASE-DYN-REP-01", "CASE-DYN-REP-02", "CASE-DYN-REP-UNASSIGNED"]
    user_names = ["user_ce_auth", "user_inv_auth", "user_unassigned"]

    cleanup_test_artifacts(db, case_codes, user_names)

    # 1. Cyber Expert user (Role 3)
    ce_user = User(
        username="user_ce_auth",
        full_name="Cyber Expert Alice",
        email="ce_alice@deps.gov",
        phone_number="9876543001",
        role_id=3,
        cyber_cell_id=1,
        password="hashed_password"
    )
    db.add(ce_user)

    # 2. Investigator user (Role 2)
    inv_user = User(
        username="user_inv_auth",
        full_name="Investigator Bob",
        email="inv_bob@deps.gov",
        phone_number="9876543002",
        role_id=2,
        cyber_cell_id=1,
        password="hashed_password"
    )
    db.add(inv_user)

    # 3. Unassigned user (Role 2)
    unassigned_user = User(
        username="user_unassigned",
        full_name="Investigator Charlie",
        email="inv_charlie@deps.gov",
        phone_number="9876543003",
        role_id=2,
        cyber_cell_id=1,
        password="hashed_password"
    )
    db.add(unassigned_user)
    db.commit()
    db.refresh(ce_user)
    db.refresh(inv_user)
    db.refresh(unassigned_user)

    # 4. Case 1: Assigned to Cyber Expert Alice & Investigator Bob
    case_1 = Case(
        case_id="CASE-DYN-REP-01",
        title="Dynamic Ransomware Investigation",
        description="Dynamic case created for report persistence verification",
        priority="High",
        status="Open",
        created_by=ce_user.id,
        investigator_id=inv_user.id,
        cyber_expert_id=ce_user.id
    )
    db.add(case_1)

    # 5. Case 2: Assigned only to Investigator Bob
    case_2 = Case(
        case_id="CASE-DYN-REP-02",
        title="Secondary Network Intrusion",
        description="Secondary case for cross-case testing",
        priority="Medium",
        status="Open",
        created_by=inv_user.id,
        investigator_id=inv_user.id,
        cyber_expert_id=None
    )
    db.add(case_2)

    db.commit()
    db.refresh(case_1)
    db.refresh(case_2)

    # 6. Add evidence to Case 1
    ev_1 = Evidence(
        evidence_id="EV-DYN-001",
        case_id=case_1.id,
        file_name="memory_dump.raw",
        file_type="LOG",
        file_size=2048576,
        file_path="C:\\Users\\HP\\DigitalEvidence-EPRA\\datasets\\evidence\\memory_dump.raw",
        status="Analyzed"
    )
    db.add(ev_1)
    db.commit()
    db.refresh(ev_1)

    eh_1 = EvidenceHash(
        evidence_id=ev_1.id,
        file_name=ev_1.file_name,
        sha256_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        current_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        integrity_status="MATCH",
        hash_match=True,
        tampered=False
    )
    db.add(eh_1)
    db.commit()

    context = {
        "ce_user": ce_user,
        "inv_user": inv_user,
        "unassigned_user": unassigned_user,
        "case_1": case_1,
        "case_2": case_2,
        "ev_1": ev_1
    }

    yield context

    # Teardown
    cleanup_test_artifacts(db, case_codes, user_names)
    db.close()


def test_01_generate_report_creates_db_record(setup_environment):
    """1. Generate report creates DB record."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        req = ReportRequest(
            case_id=ctx["case_1"].case_id,
            report_type=ReportType.COMPREHENSIVE,
            conclusions_text="Dynamic test conclusion"
        )
        res = generate_report(case_id=ctx["case_1"].case_id, payload=req, db=db, current_user=ctx["ce_user"])

        assert res["status"] == "success"
        rep_id = res["report_id"]
        assert rep_id is not None

        rec = db.query(ReportRecord).filter(ReportRecord.id == rep_id).first()
        assert rec is not None, "ReportRecord must exist in database"
        assert rec.case_id in (ctx["case_1"].case_id, str(ctx["case_1"].id))
        assert rec.is_draft is False
        assert rec.investigator_name == ctx["ce_user"].full_name
    finally:
        db.close()


def test_02_generated_pdf_file_persists(setup_environment):
    """2. Generated PDF file physically persists on disk."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()
        assert rec is not None
        pdf_path = Path(rec.file_path)
        assert pdf_path.exists(), f"File must exist at {pdf_path}"
        assert pdf_path.is_file()
        assert pdf_path.stat().st_size > 500
    finally:
        db.close()


def test_03_db_record_points_to_correct_persisted_file(setup_environment):
    """3. DB record points to correct persisted file with matching size and name."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()
        pdf_path = Path(rec.file_path)
        assert rec.file_name == pdf_path.name
        assert rec.file_size_bytes == pdf_path.stat().st_size
    finally:
        db.close()


def test_04_view_returns_persisted_report(setup_environment):
    """4. View returns persisted report data matching ReportRecord."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()
        # View by report_id
        view_by_id = get_report_view_data(db, rec.id, ctx["ce_user"])
        assert view_by_id["report_id"] == rec.id
        assert view_by_id["case_id"] == ctx["case_1"].case_id
        assert view_by_id["report_status"] == "GENERATED"
        assert view_by_id["can_download"] is True

        # View by case_id
        view_by_case = get_report_view_data(db, ctx["case_1"].case_id, ctx["ce_user"])
        assert view_by_case["report_id"] == rec.id
    finally:
        db.close()


def test_05_view_does_not_regenerate_report(setup_environment):
    """5. View does not regenerate report; timestamps and IDs remain strictly identical."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec_before = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()
        total_reports_before = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).count()

        # Call View 3 times
        for _ in range(3):
            v = get_report_view_data(db, rec_before.id, ctx["ce_user"])
            assert v["report_id"] == rec_before.id

        total_reports_after = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).count()
        rec_after = db.query(ReportRecord).filter(ReportRecord.id == rec_before.id).first()

        assert total_reports_after == total_reports_before, "View must NEVER create new ReportRecord records"
        assert rec_after.generated_at == rec_before.generated_at, "View must not alter generation timestamp"
        assert rec_after.file_path == rec_before.file_path
    finally:
        db.close()


def test_06_download_returns_persisted_report(setup_environment):
    """6. Download returns persisted report matching the DB file path."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()
        path, fname = get_report_pdf_file_path(db, rec.id, ctx["ce_user"])
        assert str(path) == str(Path(rec.file_path).resolve())
        assert path.exists()
    finally:
        db.close()


def test_07_download_returns_application_pdf(setup_environment):
    """7. Download returns Content-Type application/pdf."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()
        resp = download_report_by_path(report_or_case_id=rec.id, current_user=ctx["ce_user"], db=db)
        assert resp.media_type == "application/pdf"
        assert resp.headers["Content-Type"] == "application/pdf"
        assert "attachment" in resp.headers["Content-Disposition"]
    finally:
        db.close()


def test_08_downloaded_pdf_is_valid_non_empty(setup_environment):
    """8. Downloaded PDF is valid binary with %PDF- magic header and non-empty."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()
        resp = download_report_by_path(report_or_case_id=rec.id, current_user=ctx["ce_user"], db=db)
        assert Path(resp.path).stat().st_size > 1000
        with open(resp.path, "rb") as f:
            header = f.read(5)
            assert header == b"%PDF-", f"File header must be %PDF-, got: {header}"
    finally:
        db.close()


def test_09_report_list_history_comes_from_db(setup_environment):
    """9. Report list/history comes directly from database ReportRecord."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        hist = get_report_history(ctx["case_1"].case_id, page=1, page_size=10, db=db, current_user=ctx["ce_user"])
        assert hist["total_reports"] >= 1
        rep_entry = hist["reports"][0]
        assert rep_entry["case_id"] == ctx["case_1"].case_id
        assert rep_entry["file_format"] == "PDF"
        assert rep_entry["download_url"].startswith(f"/cases/{ctx['case_1'].case_id}/reports/download/")
    finally:
        db.close()


def test_10_authorized_cyber_expert_works(setup_environment):
    """10. Authorized Cyber Expert can generate, view, and download report."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        # Generate
        req = ReportRequest(case_id=ctx["case_1"].case_id, report_type=ReportType.EVIDENCE_SUMMARY)
        res = generate_report(ctx["case_1"].case_id, payload=req, db=db, current_user=ctx["ce_user"])
        rep_id = res["report_id"]

        # View
        v = get_report_view_data(db, rep_id, ctx["ce_user"])
        assert v["report_id"] == rep_id

        # Download
        p, _ = get_report_pdf_file_path(db, rep_id, ctx["ce_user"])
        assert p.exists()
    finally:
        db.close()


def test_11_authorized_investigator_works(setup_environment):
    """11. Authorized Investigator can view and download the SAME report."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()

        # View by Investigator
        v = get_report_view_data(db, rec.id, ctx["inv_user"])
        assert v["report_id"] == rec.id

        # Download by Investigator
        p, _ = get_report_pdf_file_path(db, rec.id, ctx["inv_user"])
        assert p.exists()
    finally:
        db.close()


def test_12_unauthorized_user_blocked(setup_environment):
    """12. Unauthorized user blocked with 403 Forbidden."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()

        # View blocked
        with pytest.raises(HTTPException) as exc_view:
            get_report_view_data(db, rec.id, ctx["unassigned_user"])
        assert exc_view.value.status_code == 403

        # Download blocked
        with pytest.raises(HTTPException) as exc_dl:
            get_report_pdf_file_path(db, rec.id, ctx["unassigned_user"])
        assert exc_dl.value.status_code == 403

        # Generate blocked
        req = ReportRequest(case_id=ctx["case_1"].case_id)
        with pytest.raises(HTTPException) as exc_gen:
            generate_report(ctx["case_1"].case_id, payload=req, db=db, current_user=ctx["unassigned_user"])
        assert exc_gen.value.status_code == 403
    finally:
        db.close()


def test_13_cross_case_report_access_blocked(setup_environment):
    """13. Cross-case report access blocked (cannot download Case 1 report using Case 2 URL)."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        rec_1 = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).first()

        # Attempt to access Case 1 report under Case 2
        with pytest.raises(HTTPException) as exc:
            download_report_by_id(case_id=ctx["case_2"].case_id, report_id=rec_1.id, db=db, current_user=ctx["inv_user"])
        assert exc.value.status_code == 404
        assert "does not belong" in str(exc.value.detail).lower()
    finally:
        db.close()


def test_14_invalid_report_id_404(setup_environment):
    """14. Invalid report ID returns 404 Not Found."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        with pytest.raises(HTTPException) as exc:
            get_report_view_data(db, "non-existent-uuid-99999", ctx["ce_user"])
        assert exc.value.status_code == 404

        with pytest.raises(HTTPException) as exc_dl:
            get_report_pdf_file_path(db, "non-existent-uuid-99999", ctx["ce_user"])
        assert exc_dl.value.status_code == 404
    finally:
        db.close()


def test_15_db_record_plus_missing_file_handled_cleanly(setup_environment):
    """15. DB record exists but file on disk missing: returns clean 404 without silent regeneration."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        # Create a report record with missing file
        fake_rec = ReportRecord(
            id="rep-missing-file-test-uuid",
            case_id=ctx["case_1"].case_id,
            case_title="Missing File Test",
            crime_type="Test",
            investigator_name=ctx["ce_user"].full_name,
            generated_by_id=str(ctx["ce_user"].id),
            generated_by_role="Cyber Expert",
            report_type="Test",
            file_format="PDF",
            file_size_bytes=1024,
            file_path=str(Path(backend_dir) / "generated_reports" / "reports" / "non_existent_file_xyz.pdf"),
            file_name="non_existent_file_xyz.pdf",
            is_draft=False
        )
        db.add(fake_rec)
        db.commit()

        # Attempt download: must raise 404 and NOT regenerate
        with pytest.raises(HTTPException) as exc:
            get_report_pdf_file_path(db, fake_rec.id, ctx["ce_user"])
        assert exc.value.status_code == 404
        assert "not found on disk" in str(exc.value.detail).lower()

        # Clean up fake record
        db.delete(fake_rec)
        db.commit()
    finally:
        db.close()


def test_16_no_arbitrary_frontend_file_path_accepted(setup_environment):
    """16. Path traversal or files outside safe storage directory are rejected with 403."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        # Create a malicious record pointing outside safe directory
        bad_rec = ReportRecord(
            id=str(uuid4()),
            case_id=ctx["case_1"].case_id,
            case_title="Traversal Test",
            crime_type="Test",
            investigator_name=ctx["ce_user"].full_name,
            generated_by_id=str(ctx["ce_user"].id),
            generated_by_role="Cyber Expert",
            report_type="Test",
            file_format="PDF",
            file_size_bytes=50,
            file_path="C:\\Windows\\System32\\drivers\\etc\\hosts",
            file_name="hosts",
            is_draft=False
        )
        db.add(bad_rec)
        db.commit()

        try:
            with pytest.raises(HTTPException) as exc:
                get_report_pdf_file_path(db, bad_rec.id, ctx["ce_user"])
            assert exc.value.status_code == 403
            assert "outside safe storage" in str(exc.value.detail).lower()
        finally:
            db.delete(bad_rec)
            db.commit()
    finally:
        db.close()


def test_17_new_dynamic_case_report_works(setup_environment):
    """17. Dynamically created brand-new case can generate, persist, view, and download."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        # Create unique new case
        timestamp_code = f"CASE-NEW-{int(datetime.now(timezone.utc).timestamp())}"
        new_case = Case(
            case_id=timestamp_code,
            title="Brand New Dynamic Test Case",
            description="Testing end-to-end report lifecycle on new case",
            priority="Critical",
            status="Open",
            created_by=ctx["ce_user"].id,
            investigator_id=ctx["inv_user"].id,
            cyber_expert_id=ctx["ce_user"].id
        )
        db.add(new_case)
        db.commit()
        db.refresh(new_case)

        # Generate
        req = ReportRequest(case_id=timestamp_code, report_type=ReportType.COMPREHENSIVE)
        gen_res = generate_report(timestamp_code, payload=req, db=db, current_user=ctx["ce_user"])
        new_rep_id = gen_res["report_id"]

        # View
        v = get_report_view_data(db, new_rep_id, ctx["ce_user"])
        assert v["report_id"] == new_rep_id
        assert v["case_id"] == timestamp_code

        # Download
        p, fn = get_report_pdf_file_path(db, new_rep_id, ctx["ce_user"])
        assert p.exists()
        assert p.stat().st_size > 1000

        # Clean up
        reps = db.query(ReportRecord).filter(ReportRecord.case_id.in_([timestamp_code, str(new_case.id)])).all()
        for r in reps:
            if r.file_path and Path(r.file_path).exists():
                try:
                    Path(r.file_path).unlink()
                except Exception:
                    pass
            db.delete(r)
        db.query(CustodyLog).filter(CustodyLog.case_id.in_([timestamp_code, str(new_case.id)])).delete(synchronize_session=False)
        db.query(ActivityLog).filter(ActivityLog.case_id.in_([timestamp_code, str(new_case.id)])).delete(synchronize_session=False)
        db.delete(new_case)
        db.commit()
    finally:
        db.close()


def test_18_separate_request_session_still_retrieves_report(setup_environment):
    """18. Separate session / simulated restart retrieves the exact same report."""
    ctx = setup_environment
    # Close old session, create brand new session
    fresh_db = SessionLocal()
    try:
        rec = fresh_db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).order_by(ReportRecord.generated_at.desc()).first()
        assert rec is not None

        # Re-query user in new session
        ce_fresh = fresh_db.query(User).filter(User.id == ctx["ce_user"].id).first()

        # View in fresh session
        v = get_report_view_data(fresh_db, rec.id, ce_fresh)
        assert v["report_id"] == rec.id

        # Download in fresh session
        p, _ = get_report_pdf_file_path(fresh_db, rec.id, ce_fresh)
        assert p.exists()
    finally:
        fresh_db.close()


def test_19_existing_investigator_report_regression_remains_working(setup_environment):
    """19. Investigator table and overview endpoints continue working properly."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        overview = get_investigator_reports_overview(db, ctx["inv_user"])
        assert "total_reports" in overview
        assert overview["total_reports"] >= 1

        tbl = get_investigator_reports_table(db, ctx["inv_user"], page=1, page_size=10)
        assert tbl["total_count"] >= 1
        assert any(item["case_id"] == ctx["case_1"].case_id for item in tbl["items"])
    finally:
        db.close()


def test_20_no_hardcoded_case_or_report_id(setup_environment):
    """20. Verified that all reports use dynamic UUIDs and database relationships."""
    ctx = setup_environment
    db = SessionLocal()
    try:
        reps = db.query(ReportRecord).filter(ReportRecord.case_id.in_([ctx["case_1"].case_id, str(ctx["case_1"].id)])).all()
        for r in reps:
            # Report IDs must be valid UUIDs
            assert len(r.id) >= 32
            assert r.case_id in (ctx["case_1"].case_id, str(ctx["case_1"].id))
            assert "6922" not in r.id  # No hardcoded IDs
    finally:
        db.close()
