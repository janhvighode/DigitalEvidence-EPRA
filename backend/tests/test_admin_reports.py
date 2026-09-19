import os
from uuid import uuid4
from datetime import datetime, timezone, timedelta
from pathlib import Path
import pytest
from fastapi import HTTPException
from sqlalchemy.orm import Session

from database.database import SessionLocal
from models.user import User
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.case import Case
from models.evidence import Evidence
from models.epra_result import EPRAResult
from models.report_record import ReportRecord
from services.pdf_service import DEFAULT_REPORTS_DIR
from services.admin_report_service import AdminReportService
from routes.admin_report_routes import (
    get_admin_case_wise_reports,
    get_admin_report_coverage,
    get_admin_case_report_overview,
    get_admin_case_report_history
)
from services.report_service import get_report_view_data, get_report_pdf_file_path


@pytest.fixture(scope="module")
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture(scope="module")
def test_setup(db: Session):
    suffix = uuid4().hex[:8]

    # Ensure Roles exist
    r1 = db.query(Role).filter(Role.id == 1).first()
    if not r1:
        r1 = Role(id=1, role_name="Admin")
        db.add(r1)
    r2 = db.query(Role).filter(Role.id == 2).first()
    if not r2:
        r2 = Role(id=2, role_name="Investigator")
        db.add(r2)
    r3 = db.query(Role).filter(Role.id == 3).first()
    if not r3:
        r3 = Role(id=3, role_name="Cyber Expert")
        db.add(r3)

    # Ensure a City exists
    city = db.query(City).first()
    if not city:
        city = City(city_name=f"City_{suffix}")
        db.add(city)
        db.flush()
    city_id = city.id
    db.commit()

    # Dedicated CyberCells for test isolation
    cell1 = CyberCell(
        cyber_cell_name=f"Admin Reports Cell 1 {suffix}",
        admin_email=f"admin_cell1_{suffix}@deps.local",
        city_id=city_id
    )
    cell2 = CyberCell(
        cyber_cell_name=f"Admin Reports Cell 2 {suffix}",
        admin_email=f"admin_cell2_{suffix}@deps.local",
        city_id=city_id
    )
    db.add_all([cell1, cell2])
    db.flush()
    cell1_id = cell1.id
    cell2_id = cell2.id

    # Create Users
    # Admin in Cell 1
    admin_cell1 = User(
        full_name=f"Admin Cell1 {suffix}",
        username=f"admin_c1_{suffix}",
        email=f"admin_c1_{suffix}@deps.local",
        phone_number="1234567801",
        password="hashed_pw",
        role_id=1,
        cyber_cell_id=cell1_id,
        is_first_login=False,
        is_active=True
    )
    # Admin in Cell 2 (isolated)
    admin_cell2 = User(
        full_name=f"Admin Cell2 {suffix}",
        username=f"admin_c2_{suffix}",
        email=f"admin_c2_{suffix}@deps.local",
        phone_number="1234567802",
        password="hashed_pw",
        role_id=1,
        cyber_cell_id=cell2_id,
        is_first_login=False,
        is_active=True
    )
    # Investigator
    inv_user = User(
        full_name=f"Investigator {suffix}",
        username=f"inv_{suffix}",
        email=f"inv_{suffix}@deps.local",
        phone_number="1234567803",
        password="hashed_pw",
        role_id=2,
        cyber_cell_id=cell1_id,
        is_first_login=False,
        is_active=True
    )
    # Cyber Expert
    ce_user = User(
        full_name=f"CyberExpert {suffix}",
        username=f"ce_{suffix}",
        email=f"ce_{suffix}@deps.local",
        phone_number="1234567804",
        password="hashed_pw",
        role_id=3,
        cyber_cell_id=cell1_id,
        is_first_login=False,
        is_active=True
    )
    db.add_all([admin_cell1, admin_cell2, inv_user, ce_user])
    db.flush()

    admin_c1_id = admin_cell1.id
    admin_c2_id = admin_cell2.id
    inv_id = inv_user.id
    ce_id = ce_user.id
    inv_name = inv_user.full_name
    ce_name = ce_user.full_name

    now = datetime.now(timezone.utc)

    # 4 Cases in Cell 1 (created_by admin_cell1)
    # Case A: No reports, Open
    case_a = Case(
        case_id=f"CASE-A-{suffix}",
        title=f"Case A Alpha {suffix}",
        description="Case with zero reports",
        crime_type="Financial Fraud",
        priority="Low",
        status="Open",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=now - timedelta(days=4)
    )
    # Case B: 1 GENERATED report, In Progress
    case_b = Case(
        case_id=f"CASE-B-{suffix}",
        title=f"Case B Beta {suffix}",
        description="Case with one generated report",
        crime_type="Cyber Stalking",
        priority="Medium",
        status="In Progress",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=now - timedelta(days=3)
    )
    # Case C: 1 FINAL report, Closed
    case_c = Case(
        case_id=f"CASE-C-{suffix}",
        title=f"Case C Gamma {suffix}",
        description="Case with one final report",
        crime_type="Ransomware Attack",
        priority="High",
        status="Closed",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=now - timedelta(days=2)
    )
    # Case D: Multiple reports (1 DRAFT, 1 GENERATED, 1 FINAL), Under Review
    case_d = Case(
        case_id=f"CASE-D-{suffix}",
        title=f"Case D Delta {suffix}",
        description="Case with multiple reports",
        crime_type="Identity Theft",
        priority="Critical",
        status="Under Review",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=now - timedelta(days=1)
    )
    # Case Other in Cell 2 (created_by admin_cell2)
    case_other = Case(
        case_id=f"CASE-OTHER-{suffix}",
        title=f"Case Other Cell 2 {suffix}",
        description="Case belonging to cell 2",
        crime_type="Hacking",
        priority="High",
        status="Open",
        created_by=admin_c2_id,
        created_at=now
    )
    db.add_all([case_a, case_b, case_c, case_d, case_other])
    db.flush()

    case_a_id = case_a.id
    case_b_id = case_b.id
    case_c_id = case_c.id
    case_d_id = case_d.id
    case_other_id = case_other.id

    case_b_cid = str(case_b.case_id)
    case_c_cid = str(case_c.case_id)
    case_d_cid = str(case_d.case_id)

    # Evidence for Case B and D
    ev_b = Evidence(
        evidence_id=f"EV-B-{suffix}",
        case_id=case_b_id,
        file_name="evidence_b.jpg",
        file_type="image/jpeg",
        file_size=1024,
        file_path="uploads/evidence/test_b.jpg",
        status="Active"
    )
    ev_d = Evidence(
        evidence_id=f"EV-D-{suffix}",
        case_id=case_d_id,
        file_name="evidence_d.jpg",
        file_type="image/jpeg",
        file_size=2048,
        file_path="uploads/evidence/test_d.jpg",
        status="Active"
    )
    db.add_all([ev_b, ev_d])
    db.flush()

    ev_b_id = ev_b.id
    ev_d_id = ev_d.id

    # EPRA result for ev_b (COMPLETE)
    epra_b = EPRAResult(
        case_id=case_b_id,
        evidence_id=ev_b_id,
        epra_score=85.0,
        priority="High",
        analysis_status="COMPLETE"
    )
    db.add(epra_b)

    # Create real report files in DEFAULT_REPORTS_DIR for file_available check
    DEFAULT_REPORTS_DIR.mkdir(parents=True, exist_ok=True)
    real_pdf_name = f"report_real_{suffix}.pdf"
    real_pdf_path = DEFAULT_REPORTS_DIR / real_pdf_name
    real_pdf_path.write_bytes(b"%PDF-1.4 Mock PDF Content For Admin Report Tests")

    # Reports:
    # For Case B: 1 GENERATED report (with real file on disk)
    rep_b = ReportRecord(
        id=f"REP-B-{suffix}",
        case_id=case_b_cid,
        case_title=case_b.title,
        crime_type=case_b.crime_type,
        investigator_name=inv_name,
        generated_by_id=str(inv_id),
        generated_by_role="Investigator",
        report_type="Comprehensive Forensic Report",
        file_format="PDF",
        file_size_bytes=len(real_pdf_path.read_bytes()),
        file_path=str(real_pdf_path),
        file_name=real_pdf_name,
        is_draft=False,
        generated_at=now - timedelta(hours=10)
    )

    # For Case C: 1 FINAL report (missing file on disk to test missing binary handling)
    rep_c = ReportRecord(
        id=f"REP-C-{suffix}",
        case_id=case_c_cid,
        case_title=case_c.title,
        crime_type=case_c.crime_type,
        investigator_name=ce_name,
        generated_by_id=str(ce_id),
        generated_by_role="Cyber Expert",
        report_type="Comprehensive Forensic Report",
        file_format="PDF",
        file_size_bytes=5000,
        file_path=str(DEFAULT_REPORTS_DIR / f"nonexistent_{suffix}.pdf"),
        file_name=f"nonexistent_{suffix}.pdf",
        is_draft=False,
        generated_at=now - timedelta(hours=8)
    )

    # For Case D: 3 reports
    # Report 1 (oldest): DRAFT
    rep_d1 = ReportRecord(
        id=f"REP-D1-{suffix}",
        case_id=case_d_cid,
        case_title=case_d.title,
        crime_type=case_d.crime_type,
        investigator_name=inv_name,
        generated_by_id=str(inv_id),
        generated_by_role="Investigator",
        report_type="Evidence Summary Report",
        file_format="PDF",
        file_size_bytes=1000,
        file_path=str(DEFAULT_REPORTS_DIR / f"draft_{suffix}.pdf"),
        file_name=f"draft_{suffix}.pdf",
        is_draft=True,
        generated_at=now - timedelta(hours=5)
    )
    # Report 2 (middle): GENERATED
    rep_d2 = ReportRecord(
        id=f"REP-D2-{suffix}",
        case_id=case_d_cid,
        case_title=case_d.title,
        crime_type=case_d.crime_type,
        investigator_name=ce_name,
        generated_by_id=str(ce_id),
        generated_by_role="Cyber Expert",
        report_type="Chain of Custody Report",
        file_format="PDF",
        file_size_bytes=2000,
        file_path=str(DEFAULT_REPORTS_DIR / f"generated_{suffix}.pdf"),
        file_name=f"generated_{suffix}.pdf",
        is_draft=False,
        generated_at=now - timedelta(hours=3)
    )
    # Report 3 (newest): FINAL (Comprehensive)
    rep_d3 = ReportRecord(
        id=f"REP-D3-{suffix}",
        case_id=case_d_cid,
        case_title=case_d.title,
        crime_type=case_d.crime_type,
        investigator_name=inv_name,
        generated_by_id=str(inv_id),
        generated_by_role="Investigator",
        report_type="Comprehensive Forensic Report",
        file_format="PDF",
        file_size_bytes=len(real_pdf_path.read_bytes()),
        file_path=str(real_pdf_path),
        file_name=real_pdf_name,
        is_draft=False,
        generated_at=now - timedelta(hours=1)
    )

    db.add_all([rep_b, rep_c, rep_d1, rep_d2, rep_d3])
    db.commit()

    try:
        yield {
            "suffix": suffix,
            "admin_cell1": admin_cell1,
            "admin_cell2": admin_cell2,
            "inv_user": inv_user,
            "ce_user": ce_user,
            "case_a": case_a,
            "case_b": case_b,
            "case_c": case_c,
            "case_d": case_d,
            "case_other": case_other,
            "rep_b": rep_b,
            "rep_c": rep_c,
            "rep_d1": rep_d1,
            "rep_d2": rep_d2,
            "rep_d3": rep_d3,
            "real_pdf_path": real_pdf_path
        }
    finally:
        try:
            if real_pdf_path.exists():
                real_pdf_path.unlink()
        except Exception:
            pass
        try:
            rep_ids = [f"REP-B-{suffix}", f"REP-C-{suffix}", f"REP-D1-{suffix}", f"REP-D2-{suffix}", f"REP-D3-{suffix}"]
            db.query(ReportRecord).filter(ReportRecord.id.in_(rep_ids)).delete(synchronize_session=False)
            db.query(EPRAResult).filter(EPRAResult.case_id.in_([case_b_id, case_d_id])).delete(synchronize_session=False)
            db.query(Evidence).filter(Evidence.case_id.in_([case_b_id, case_d_id])).delete(synchronize_session=False)
            db.query(Case).filter(Case.id.in_([case_a_id, case_b_id, case_c_id, case_d_id, case_other_id])).delete(synchronize_session=False)
            db.query(User).filter(User.id.in_([admin_c1_id, admin_c2_id, inv_id, ce_id])).delete(synchronize_session=False)
            db.query(CyberCell).filter(CyberCell.id.in_([cell1_id, cell2_id])).delete(synchronize_session=False)
            db.commit()
        except Exception:
            db.rollback()


# ==============================================================================
# 1. CASE-WISE LISTING & CASE COVERAGE TESTS
# ==============================================================================

def test_case_wise_reports_all_four_cases_present(db, test_setup):
    """
    Verify:
    1. All 4 cases (A, B, C, D) in Cell 1 appear in Admin case-wise reports.
    2. Case from Cell 2 (case_other) does NOT appear (strict branch isolation).
    3. Case A (no report) -> report_status='NOT_GENERATED', reports_count=0, latest_report=None.
    4. Case B -> report_status='GENERATED', reports_count=1, latest_report present.
    5. Case C -> report_status='FINAL' (closed case), reports_count=1.
    6. Case D -> reports_count=3, latest_report is rep_d3 (newest).
    """
    admin = test_setup["admin_cell1"]
    res = get_admin_case_wise_reports(
        current_user=admin,
        db=db,
        page=1,
        page_size=20
    )

    items_by_case = {item.case_id: item for item in res.items}

    # Verify Cell 2 case is isolated
    assert test_setup["case_other"].case_id not in items_by_case, "Cross-cell case must NOT appear"

    # Verify Case A
    case_a_id = test_setup["case_a"].case_id
    assert case_a_id in items_by_case
    item_a = items_by_case[case_a_id]
    assert item_a.report_status == "NOT_GENERATED"
    assert item_a.reports_count == 0
    assert item_a.latest_report is None
    assert item_a.journey.report_generated is False
    assert item_a.journey.finalized is False

    # Verify Case B
    case_b_id = test_setup["case_b"].case_id
    assert case_b_id in items_by_case
    item_b = items_by_case[case_b_id]
    assert item_b.report_status == "GENERATED"
    assert item_b.reports_count == 1
    assert item_b.latest_report is not None
    assert item_b.latest_report.report_id == test_setup["rep_b"].id
    assert item_b.latest_report.file_available is True
    assert item_b.journey.evidence_collected is True
    assert item_b.journey.analysis_completed is True
    assert item_b.journey.report_generated is True
    assert item_b.journey.finalized is False

    # Verify Case C
    case_c_id = test_setup["case_c"].case_id
    assert case_c_id in items_by_case
    item_c = items_by_case[case_c_id]
    assert item_c.report_status == "FINAL"
    assert item_c.reports_count == 1
    assert item_c.latest_report is not None
    assert item_c.latest_report.report_id == test_setup["rep_c"].id
    assert item_c.latest_report.file_available is False  # file missing on disk
    assert item_c.journey.finalized is True

    # Verify Case D
    case_d_id = test_setup["case_d"].case_id
    assert case_d_id in items_by_case
    item_d = items_by_case[case_d_id]
    assert item_d.reports_count == 3
    assert item_d.latest_report is not None
    # Latest report should be rep_d3 (newest timestamp)
    assert item_d.latest_report.report_id == test_setup["rep_d3"].id


# ==============================================================================
# 2. COVERAGE CALCULATION TESTS
# ==============================================================================

def test_report_coverage_calculation(db, test_setup):
    """
    Verify:
    - total_cases = 4
    - cases_with_reports = 3 (B, C, D)
    - cases_without_reports = 1 (A)
    - coverage_percentage = 75.0
    - multiple reports on Case D count as 1 case with reports.
    - status_counts contains correct distribution.
    """
    admin = test_setup["admin_cell1"]
    cov = get_admin_report_coverage(current_user=admin, db=db)

    assert cov.total_cases == 4
    assert cov.cases_with_reports == 3
    assert cov.cases_without_reports == 1
    assert cov.coverage_percentage == 75.0
    assert cov.status_counts["not_generated"] == 1
    assert cov.status_counts["generated"] == 2  # B, D
    assert cov.status_counts["final"] == 1      # C


# ==============================================================================
# 3. REPORT HISTORY TESTS
# ==============================================================================

def test_case_report_history_newest_to_oldest(db, test_setup):
    """
    Verify:
    1. Returns all 3 reports for Case D.
    2. Ordered newest -> oldest: rep_d3 (FINAL/GEN), rep_d2 (GEN), rep_d1 (DRAFT).
    3. Exposes dynamic generated_by and generated_by_role.
    4. Exposes file_available accurately without regenerating.
    """
    admin = test_setup["admin_cell1"]
    case_d = test_setup["case_d"]
    hist = get_admin_case_report_history(case_id=case_d.case_id, current_user=admin, db=db)

    assert hist.total_reports == 3
    assert len(hist.reports) == 3

    # Newest to oldest check
    assert hist.reports[0].report_id == test_setup["rep_d3"].id
    assert hist.reports[1].report_id == test_setup["rep_d2"].id
    assert hist.reports[2].report_id == test_setup["rep_d1"].id

    # Verify fields
    assert hist.reports[0].is_draft is False
    assert hist.reports[2].is_draft is True
    assert hist.reports[0].file_available is True
    assert hist.reports[0].generated_by_name == test_setup["inv_user"].full_name
    assert hist.reports[0].generated_by_role == "Investigator"


# ==============================================================================
# 4. SEARCH, FILTER, SORT & PAGINATION TESTS
# ==============================================================================

def test_search_and_filters(db, test_setup):
    """
    Verify server-side search across Case ID, Case Title, Investigator, and Cyber Expert.
    Verify filtering by case_status and report_status.
    """
    admin = test_setup["admin_cell1"]
    suffix = test_setup["suffix"]

    # 1. Search by Case ID
    res_search_id = get_admin_case_wise_reports(
        search=f"CASE-A-{suffix}",
        current_user=admin,
        db=db
    )
    assert res_search_id.total_items == 1
    assert res_search_id.items[0].case_id == test_setup["case_a"].case_id

    # 2. Search by Title keyword
    res_search_title = get_admin_case_wise_reports(
        search="Gamma",
        current_user=admin,
        db=db
    )
    assert res_search_title.total_items == 1
    assert res_search_title.items[0].case_id == test_setup["case_c"].case_id

    # 3. Filter by case_status='Closed'
    res_filter_closed = get_admin_case_wise_reports(
        case_status="Closed",
        current_user=admin,
        db=db
    )
    assert res_filter_closed.total_items == 1
    assert res_filter_closed.items[0].case_id == test_setup["case_c"].case_id

    # 4. Filter by report_status='NOT_GENERATED'
    res_filter_not_gen = get_admin_case_wise_reports(
        report_status="NOT_GENERATED",
        current_user=admin,
        db=db
    )
    assert res_filter_not_gen.total_items == 1
    assert res_filter_not_gen.items[0].case_id == test_setup["case_a"].case_id

    # 5. Sorting by oldest
    res_sort_oldest = get_admin_case_wise_reports(
        sort="oldest",
        current_user=admin,
        db=db
    )
    assert res_sort_oldest.items[0].case_id == test_setup["case_a"].case_id


# ==============================================================================
# 5. AUTHORIZATION CONTROLS TESTS
# ==============================================================================

def test_authorization_controls(db, test_setup):
    """
    Verify:
    1. Investigator (role_id=2) blocked with 403.
    2. Cyber Expert (role_id=3) blocked with 403.
    3. Admin Cell 2 cannot access history of Case A from Cell 1 (403).
    4. Nonexistent case returns 404.
    """
    inv = test_setup["inv_user"]
    ce = test_setup["ce_user"]
    admin2 = test_setup["admin_cell2"]
    case_a = test_setup["case_a"]

    # 1. Investigator blocked from Admin endpoints
    with pytest.raises(HTTPException) as exc_inv:
        get_admin_case_wise_reports(current_user=inv, db=db)
    assert exc_inv.value.status_code == 403

    with pytest.raises(HTTPException) as exc_inv_cov:
        get_admin_report_coverage(current_user=inv, db=db)
    assert exc_inv_cov.value.status_code == 403

    # 2. Cyber Expert blocked from Admin endpoints
    with pytest.raises(HTTPException) as exc_ce:
        get_admin_case_wise_reports(current_user=ce, db=db)
    assert exc_ce.value.status_code == 403

    # 3. Cross-cell Admin access blocked
    with pytest.raises(HTTPException) as exc_cross:
        get_admin_case_report_history(case_id=case_a.case_id, current_user=admin2, db=db)
    assert exc_cross.value.status_code == 403

    # 4. Nonexistent case returns 404
    with pytest.raises(HTTPException) as exc_404:
        get_admin_case_report_overview(case_id="NONEXISTENT-CASE-99999", current_user=test_setup["admin_cell1"], db=db)
    assert exc_404.value.status_code == 404


# ==============================================================================
# 6. VIEW & DOWNLOAD REGRESSION TESTS
# ==============================================================================

def test_view_and_download_regression(db, test_setup):
    """
    Verify:
    1. Admin can view existing structured report via get_report_view_data.
    2. View does NOT create new ReportRecord.
    3. Download returns existing persisted file path without regenerating.
    4. Missing historical PDF raises clean 404 without regenerating fake PDF.
    """
    admin = test_setup["admin_cell1"]
    rep_b = test_setup["rep_b"]
    rep_c = test_setup["rep_c"]

    initial_count = db.query(ReportRecord).count()

    # View existing report
    view_data = get_report_view_data(db, rep_b.id, admin)
    assert view_data["report_id"] == rep_b.id

    count_after_view = db.query(ReportRecord).count()
    assert count_after_view == initial_count, "View must NEVER create new ReportRecord records"

    # Download existing report with file on disk
    pdf_path, filename = get_report_pdf_file_path(db, rep_b.id, admin)
    assert Path(pdf_path).is_file()
    assert count_after_view == db.query(ReportRecord).count(), "Download must NEVER create new ReportRecord records"

    # Download report with missing binary on disk -> clean 404
    with pytest.raises(HTTPException) as exc_missing:
        get_report_pdf_file_path(db, rep_c.id, admin)
    assert exc_missing.value.status_code == 404
    assert "not found on disk" in str(exc_missing.value.detail).lower()
