"""
Comprehensive Test Suite for Investigator Reports Module:
1. Report generation by assigned Investigator
2. Report persistence in database and on disk
3. Case Workspace -> Reports view and download
4. Sidebar -> Reports sharing the exact SAME report record
5. View Report structured sections verification
6. Centralized valid PDF download with application/pdf Content-Type
7. Refresh / session persistence (survives restart)
8. Strict Investigator authorization and cross-case isolation (403 Forbidden)
9. NOT_GENERATED download rejection (400 Bad Request, no fake PDF)
10. Reports Overview counts
11. Reports Trend 6-month monthly data
12. New investigator with 0 assigned cases (empty reports state)
13. Search and filtering (case_status, report_status, keyword)
14. Real PDF integrity (valid %PDF header, non-empty, openable)
"""

import sys
import os
from pathlib import Path
from datetime import datetime, timezone

# Add backend directory to sys.path
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException
from database.database import SessionLocal, Base, engine
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.epra_result import EPRAResult
from models.custody_log import CustodyLog
from models.case_timeline import CaseTimeline
from models.report_record import ReportRecord
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell

from schemas.technical_report import ReportRequest
from services.technical_report_service import TechnicalReportService
from services.report_service import (
    get_investigator_reports_overview,
    get_investigator_reports_trend,
    get_investigator_reports_table,
    get_report_view_data,
    get_report_pdf_file_path
)
from routes.report_routes import (
    fetch_reports_overview,
    fetch_reports_trend,
    fetch_reports,
    view_report_structured,
    download_report_by_path,
    download_report_alias
)
from routes.technical_report_routes import (
    generate_report,
    view_case_report,
    download_report_by_id,
    get_report_history
)


TEST_CASE_ID_1 = "CASE-INV-REP-101"
TEST_CASE_ID_2 = "CASE-INV-REP-102"
TEST_CASE_ID_UNASSIGNED = "CASE-INV-REP-999"


def clean_fixtures():
    db = SessionLocal()
    try:
        # Find test cases
        test_case_ids = [TEST_CASE_ID_1, TEST_CASE_ID_2, TEST_CASE_ID_UNASSIGNED]
        cases = db.query(Case).filter(Case.case_id.in_(test_case_ids)).all()
        c_numeric_ids = [c.id for c in cases]
        c_str_ids = [c.case_id for c in cases] + [str(c.id) for c in cases]

        if c_str_ids:
            # Delete report records
            reps = db.query(ReportRecord).filter(ReportRecord.case_id.in_(c_str_ids)).all()
            for r in reps:
                if r.file_path and Path(r.file_path).exists():
                    try:
                        Path(r.file_path).unlink()
                    except Exception:
                        pass
                db.delete(r)

            # Delete custody logs
            db.query(CustodyLog).filter(CustodyLog.case_id.in_(c_str_ids)).delete(synchronize_session=False)

            # Delete epra
            db.query(EPRAResult).filter(EPRAResult.case_id.in_(c_numeric_ids)).delete(synchronize_session=False)

            # Delete evidence records
            db.query(EvidenceRecord).filter(EvidenceRecord.case_id.in_(c_str_ids)).delete(synchronize_session=False)

            # Delete evidence hashes & evidences
            evs = db.query(Evidence).filter(Evidence.case_id.in_(c_numeric_ids)).all()
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

            # Delete timelines
            db.query(CaseTimeline).filter(CaseTimeline.case_id.in_(c_numeric_ids)).delete(synchronize_session=False)

            db.commit()

            # Delete cases
            db.query(Case).filter(Case.id.in_(c_numeric_ids)).delete(synchronize_session=False)
            db.commit()

        # Delete test users
        for uname in ["test_inv_rep_a", "test_inv_rep_b", "test_inv_rep_fresh"]:
            u = db.query(User).filter(User.username == uname).first()
            if u:
                db.delete(u)
        db.commit()
    except Exception as e:
        print(f"Cleanup warning: {e}")
        db.rollback()
    finally:
        db.close()


def setup_fixtures():
    db = SessionLocal()
    try:
        # 1. Investigator A (Assigned Case 1 & Case 2)
        inv_a = db.query(User).filter(User.username == "test_inv_rep_a").first()
        if not inv_a:
            inv_a = User(
                username="test_inv_rep_a",
                full_name="Investigator Alpha",
                email="inv_alpha@deps.gov",
                phone_number="9876543210",
                role_id=2,
                cyber_cell_id=1,
                password="hashed_password"
            )
            db.add(inv_a)
            db.commit()
            db.refresh(inv_a)

        # 2. Investigator B (Unassigned to Case 1)
        inv_b = db.query(User).filter(User.username == "test_inv_rep_b").first()
        if not inv_b:
            inv_b = User(
                username="test_inv_rep_b",
                full_name="Investigator Beta",
                email="inv_beta@deps.gov",
                phone_number="9876543211",
                role_id=2,
                cyber_cell_id=1,
                password="hashed_password"
            )
            db.add(inv_b)
            db.commit()
            db.refresh(inv_b)

        # 3. Investigator Fresh (Zero assigned cases)
        inv_fresh = db.query(User).filter(User.username == "test_inv_rep_fresh").first()
        if not inv_fresh:
            inv_fresh = User(
                username="test_inv_rep_fresh",
                full_name="Investigator Fresh",
                email="inv_fresh@deps.gov",
                phone_number="9876543212",
                role_id=2,
                cyber_cell_id=1,
                password="hashed_password"
            )
            db.add(inv_fresh)
            db.commit()
            db.refresh(inv_fresh)

        # 4. Expert
        expert = db.query(User).filter(User.role_id == 3).first()
        admin = db.query(User).filter(User.role_id == 1).first()

        # 5. Case 1 (Ongoing, assigned to inv_a)
        case_1 = Case(
            case_id=TEST_CASE_ID_1,
            title="Cyber Banking Fraud Alpha",
            description="Financial Fraud Investigation",
            investigator_id=inv_a.id,
            cyber_expert_id=expert.id if expert else None,
            created_by=admin.id if admin else inv_a.id,
            status="In Progress",
            priority="High"
        )
        db.add(case_1)

        # 6. Case 2 (Closed / Final, assigned to inv_a)
        case_2 = Case(
            case_id=TEST_CASE_ID_2,
            title="Ransomware Intrusion Beta",
            description="Malware Ransomware Attack",
            investigator_id=inv_a.id,
            cyber_expert_id=expert.id if expert else None,
            created_by=admin.id if admin else inv_a.id,
            status="Closed",
            priority="Critical"
        )
        db.add(case_2)

        # 7. Case Unassigned (assigned to inv_b)
        case_unassigned = Case(
            case_id=TEST_CASE_ID_UNASSIGNED,
            title="Unrelated Phishing Campaign",
            description="Phishing Attack",
            investigator_id=inv_b.id,
            cyber_expert_id=expert.id if expert else None,
            created_by=admin.id if admin else inv_b.id,
            status="Open",
            priority="Medium"
        )
        db.add(case_unassigned)
        db.commit()
        db.refresh(case_1)
        db.refresh(case_2)
        db.refresh(case_unassigned)

        # Add sample evidence to Case 1
        ev1 = Evidence(
            evidence_id=f"EV-{TEST_CASE_ID_1}-001",
            case_id=case_1.id,
            file_name="bank_ledger.csv",
            file_type="csv",
            file_size=1024,
            file_path="uploads/test_ledger.csv",
            status="Active"
        )
        db.add(ev1)
        db.commit()
        db.refresh(ev1)

        eh1 = EvidenceHash(
            evidence_id=ev1.id,
            file_name=ev1.file_name,
            sha256_hash="a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef",
            current_hash="a1b2c3d4e5f678901234567890abcdef1234567890abcdef1234567890abcdef",
            integrity_status="MATCH",
            hash_match=True,
            tampered=False
        )
        db.add(eh1)

        # Add EPRA Result for Case 1
        epra1 = EPRAResult(
            case_id=case_1.id,
            evidence_id=ev1.id,
            epra_score=88.5,
            priority="High",
            analysis_status="COMPLETE",
            semantic_status="MEASURED"
        )
        db.add(epra1)
        db.commit()

        return inv_a, inv_b, inv_fresh, case_1, case_2, case_unassigned
    finally:
        db.close()


# ==============================================================================
# TESTS
# ==============================================================================

def test_1_investigator_report_generation_and_persistence():
    """Test 1: Investigator generates report for assigned case; persists in MySQL and on disk."""
    db = SessionLocal()
    try:
        inv_a = db.query(User).filter(User.username == "test_inv_rep_a").first()
        case_1 = db.query(Case).filter(Case.case_id == TEST_CASE_ID_1).first()

        req = ReportRequest(
            case_id=case_1.case_id,
            report_type="Comprehensive Forensic Report"
        )
        res = generate_report(case_id=case_1.case_id, payload=req, db=db, current_user=inv_a)

        assert res["status"] == "success", "Report generation must succeed"
        assert res["report_id"] is not None, "Generated report must have report_id"
        rep_id = res["report_id"]

        # Verify ReportRecord was saved in MySQL database
        rec = db.query(ReportRecord).filter(ReportRecord.id == rep_id).first()
        assert rec is not None, "ReportRecord must persist in database"
        assert rec.case_id in (case_1.case_id, str(case_1.id)), "ReportRecord must be linked to correct case_id"
        assert rec.is_draft == False, "Generated report must have is_draft=False"
        assert rec.file_path is not None, "ReportRecord must have a valid file_path"

        # Verify PDF exists on disk and is non-empty
        pdf_path = Path(rec.file_path)
        assert pdf_path.exists(), f"Generated PDF file must exist on disk at {pdf_path}"
        assert pdf_path.stat().st_size > 1000, "Generated PDF must have valid non-empty byte size"

        print("PASS: test_1_investigator_report_generation_and_persistence")
        return rep_id
    finally:
        db.close()


def test_2_case_workspace_view_and_download(report_id: str):
    """Test 2: Case Workspace -> Reports retrieves the saved report and downloads valid PDF."""
    db = SessionLocal()
    try:
        inv_a = db.query(User).filter(User.username == "test_inv_rep_a").first()
        case_1 = db.query(Case).filter(Case.case_id == TEST_CASE_ID_1).first()

        # 1. View from Case Workspace
        view_res = view_case_report(case_id=case_1.case_id, db=db, current_user=inv_a)
        assert view_res["report_id"] == report_id, "Case Workspace must retrieve the exact saved report_id"
        assert view_res["case_id"] == case_1.case_id, "Case ID must match"
        assert view_res["report_status"] == "GENERATED", "Case 1 is ongoing so status must be GENERATED"
        assert view_res["can_download"] == True, "Download must be enabled for GENERATED report"

        # 2. Download from Case Workspace
        file_resp = download_report_by_id(case_id=case_1.case_id, report_id=report_id, db=db, current_user=inv_a)
        assert file_resp.media_type == "application/pdf", "Media type must be application/pdf"
        assert f"{case_1.case_id}_Forensic_Report.pdf" in file_resp.headers["Content-Disposition"], "Content-Disposition filename must be formatted correctly"
        assert Path(file_resp.path).exists(), "Downloaded file must exist on disk"

        # Check raw bytes header
        with open(file_resp.path, "rb") as f:
            header = f.read(5)
            assert header == b"%PDF-", f"File must be a valid PDF binary starting with %PDF-, got: {header}"

        print("PASS: test_2_case_workspace_view_and_download")
    finally:
        db.close()


def test_3_sidebar_reports_shares_same_report(report_id: str):
    """Test 3: Sidebar -> Reports displays the exact same report record without duplication."""
    db = SessionLocal()
    try:
        inv_a = db.query(User).filter(User.username == "test_inv_rep_a").first()
        case_1 = db.query(Case).filter(Case.case_id == TEST_CASE_ID_1).first()

        # 1. Fetch table from Sidebar Reports endpoint
        page_res = fetch_reports(current_user=inv_a, db=db)
        items = page_res["items"] if isinstance(page_res, dict) else page_res.items

        matching_row = next((item for item in items if item["case_id"] == case_1.case_id), None)
        assert matching_row is not None, f"Sidebar Reports must list Case {case_1.case_id}"
        assert matching_row["report_id"] == report_id, "Sidebar Reports must reference the exact same report_id"
        assert matching_row["report_status"] == "GENERATED", "Report status in Sidebar must match"
        assert matching_row["can_view"] == True, "can_view must be True"
        assert matching_row["can_download"] == True, "can_download must be True"

        # 2. View from Sidebar Reports endpoint
        view_res = view_report_structured(report_or_case_id=report_id, current_user=inv_a, db=db)
        assert view_res["report_id"] == report_id, "Sidebar View must retrieve the exact same report"
        assert view_res["case_id"] == case_1.case_id

        # Verify all required sections are present
        required_sections = [
            "report_info", "case_information", "investigator_information",
            "cyber_expert_information", "evidence_summary", "evidence_metadata",
            "integrity_verification", "chain_of_custody", "epra_analysis",
            "cbir_analysis", "suspect_ranking", "relationship_analysis",
            "timeline_reconstruction", "investigation_findings", "conclusion"
        ]
        for sec in required_sections:
            assert sec in view_res, f"Structured view must contain section '{sec}'"

        # 3. Download from Sidebar Reports endpoint
        dl_resp = download_report_by_path(report_or_case_id=report_id, current_user=inv_a, db=db)
        assert dl_resp.media_type == "application/pdf"
        assert f"{case_1.case_id}_Forensic_Report.pdf" in dl_resp.headers["Content-Disposition"]

        print("PASS: test_3_sidebar_reports_shares_same_report")
    finally:
        db.close()


def test_4_persistence_across_sessions_and_restart(report_id: str):
    """Test 4: Report persists across separate DB sessions (simulating page refresh / restart)."""
    # Create brand new session
    fresh_db = SessionLocal()
    try:
        inv_a = fresh_db.query(User).filter(User.username == "test_inv_rep_a").first()
        rec = fresh_db.query(ReportRecord).filter(ReportRecord.id == report_id).first()
        assert rec is not None, "ReportRecord must persist across fresh sessions"

        # Verify file path on disk remains accessible
        pdf_path = Path(rec.file_path)
        assert pdf_path.exists(), "Persistent PDF must remain intact on disk"
        assert pdf_path.stat().st_size > 0

        # View data from fresh session
        data = get_report_view_data(fresh_db, report_id, inv_a)
        assert data["report_id"] == report_id
        assert data["report_status"] == "GENERATED"

        print("PASS: test_4_persistence_across_sessions_and_restart")
    finally:
        fresh_db.close()


def test_5_strict_authorization_and_cross_case_isolation(report_id: str):
    """Test 5: Investigator Beta cannot view, download, or generate reports for Investigator Alpha's cases."""
    db = SessionLocal()
    try:
        inv_b = db.query(User).filter(User.username == "test_inv_rep_b").first()
        case_1 = db.query(Case).filter(Case.case_id == TEST_CASE_ID_1).first()

        # 1. Inv B cannot view Inv A's report
        try:
            view_report_structured(report_or_case_id=report_id, current_user=inv_b, db=db)
            assert False, "Unauthorized investigator must receive 403 Forbidden on view"
        except HTTPException as e:
            assert e.status_code == 403, f"Expected 403 Forbidden, got {e.status_code}"

        # 2. Inv B cannot download Inv A's report
        try:
            download_report_by_path(report_or_case_id=report_id, current_user=inv_b, db=db)
            assert False, "Unauthorized investigator must receive 403 Forbidden on download"
        except HTTPException as e:
            assert e.status_code == 403, f"Expected 403 Forbidden, got {e.status_code}"

        # 3. Inv B cannot generate report for Inv A's case
        try:
            req = ReportRequest(case_id=case_1.case_id)
            generate_report(case_id=case_1.case_id, payload=req, db=db, current_user=inv_b)
            assert False, "Unauthorized investigator must receive 403 Forbidden on generate"
        except HTTPException as e:
            assert e.status_code == 403, f"Expected 403 Forbidden, got {e.status_code}"

        # 4. Inv B cannot see Inv A's cases in their Reports table
        table_b = fetch_reports(current_user=inv_b, db=db)
        items_b = table_b["items"] if isinstance(table_b, dict) else table_b.items
        for item in items_b:
            assert item["case_id"] != case_1.case_id, "Inv B must not see Inv A's case in reports table"

        print("PASS: test_5_strict_authorization_and_cross_case_isolation")
    finally:
        db.close()


def test_6_not_generated_download_rejected():
    """Test 6: Case with NOT_GENERATED report status rejects download with 400 Bad Request."""
    db = SessionLocal()
    try:
        inv_a = db.query(User).filter(User.username == "test_inv_rep_a").first()
        case_2 = db.query(Case).filter(Case.case_id == TEST_CASE_ID_2).first()

        # Case 2 has not had a report generated yet
        try:
            download_report_alias(report_or_case_id=case_2.case_id, current_user=inv_a, db=db)
            assert False, "Download for ungenerated report must raise 400 Bad Request"
        except HTTPException as e:
            assert e.status_code == 400, f"Expected 400 Bad Request, got {e.status_code}"
            assert "Report has not been generated" in e.detail

        print("PASS: test_6_not_generated_download_rejected")
    finally:
        db.close()


def test_7_reports_overview_counts():
    """Test 7: Reports Overview cards return accurate, dynamically calculated counts."""
    db = SessionLocal()
    try:
        inv_a = db.query(User).filter(User.username == "test_inv_rep_a").first()
        case_2 = db.query(Case).filter(Case.case_id == TEST_CASE_ID_2).first()

        # Generate report for Case 2 (which is Closed -> FINAL)
        req = ReportRequest(case_id=case_2.case_id)
        res2 = generate_report(case_id=case_2.case_id, payload=req, db=db, current_user=inv_a)
        assert res2["report_id"] is not None

        overview = fetch_reports_overview(current_user=inv_a, db=db)

        assert overview["total_reports"] >= 2, f"Total reports must be at least 2, got {overview['total_reports']}"
        assert overview["ongoing_reports"] >= 1, f"Case 1 is ongoing, ongoing_reports must be >= 1, got {overview['ongoing_reports']}"
        assert overview["completed_final_reports"] >= 1, f"Case 2 is closed, completed_final_reports must be >= 1, got {overview['completed_final_reports']}"
        assert isinstance(overview["draft_reports"], int)
        assert isinstance(overview["not_generated_reports"], int)

        print("PASS: test_7_reports_overview_counts")
    finally:
        db.close()


def test_8_reports_trend_line_chart():
    """Test 8: Reports Trend returns 6 calendar months of real data."""
    db = SessionLocal()
    try:
        inv_a = db.query(User).filter(User.username == "test_inv_rep_a").first()
        trend = fetch_reports_trend(current_user=inv_a, db=db)

        assert len(trend) == 6, f"Trend must return exactly 6 monthly data points, got {len(trend)}"
        for item in trend:
            assert "month" in item
            assert "year" in item
            assert "reports_generated" in item
            assert "final_reports" in item
            assert isinstance(item["reports_generated"], int)
            assert isinstance(item["final_reports"], int)

        # Current month should have at least 2 generated reports (Case 1 and Case 2)
        cur_point = trend[-1]
        assert cur_point["reports_generated"] >= 2, f"Current month should have >= 2 reports, got {cur_point['reports_generated']}"

        print("PASS: test_8_reports_trend_line_chart")
    finally:
        db.close()


def test_9_fresh_investigator_sees_empty_system():
    """Test 9: Newly created Investigator with 0 cases sees an empty reports system."""
    db = SessionLocal()
    try:
        inv_fresh = db.query(User).filter(User.username == "test_inv_rep_fresh").first()

        overview = fetch_reports_overview(current_user=inv_fresh, db=db)
        assert overview["total_reports"] == 0
        assert overview["ongoing_reports"] == 0
        assert overview["completed_final_reports"] == 0
        assert overview["draft_reports"] == 0
        assert overview["not_generated_reports"] == 0

        trend = fetch_reports_trend(current_user=inv_fresh, db=db)
        assert len(trend) == 6
        for point in trend:
            assert point["reports_generated"] == 0
            assert point["final_reports"] == 0

        table = fetch_reports(current_user=inv_fresh, db=db)
        assert table["total_count"] == 0
        assert len(table["items"]) == 0

        print("PASS: test_9_fresh_investigator_sees_empty_system")
    finally:
        db.close()


def test_10_search_and_filters():
    """Test 10: Filtering and keyword search on the Reports table."""
    db = SessionLocal()
    try:
        inv_a = db.query(User).filter(User.username == "test_inv_rep_a").first()

        # Search by Case 1
        res_kw = fetch_reports(keyword=TEST_CASE_ID_1, current_user=inv_a, db=db)
        assert res_kw["total_count"] == 1
        assert res_kw["items"][0]["case_id"] == TEST_CASE_ID_1

        # Filter by status: Closed
        res_closed = fetch_reports(case_status="Closed", current_user=inv_a, db=db)
        assert any(item["case_id"] == TEST_CASE_ID_2 for item in res_closed["items"])
        assert not any(item["case_id"] == TEST_CASE_ID_1 for item in res_closed["items"])

        # Filter by report_status: FINAL
        res_final = fetch_reports(report_status="FINAL", current_user=inv_a, db=db)
        assert any(item["case_id"] == TEST_CASE_ID_2 for item in res_final["items"])

        print("PASS: test_10_search_and_filters")
    finally:
        db.close()


def run_all_tests():
    print("=" * 80)
    print("STARTING INVESTIGATOR REPORTS BACKEND TEST SUITE")
    print("=" * 80)

    clean_fixtures()
    try:
        setup_fixtures()
        rep_id = test_1_investigator_report_generation_and_persistence()
        test_2_case_workspace_view_and_download(rep_id)
        test_3_sidebar_reports_shares_same_report(rep_id)
        test_4_persistence_across_sessions_and_restart(rep_id)
        test_5_strict_authorization_and_cross_case_isolation(rep_id)
        test_6_not_generated_download_rejected()
        test_7_reports_overview_counts()
        test_8_reports_trend_line_chart()
        test_9_fresh_investigator_sees_empty_system()
        test_10_search_and_filters()

        print("=" * 80)
        print("ALL 10 INVESTIGATOR REPORTS TESTS PASSED SUCCESSFULLY!")
        print("=" * 80)
    finally:
        clean_fixtures()


if __name__ == "__main__":
    run_all_tests()
