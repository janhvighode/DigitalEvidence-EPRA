"""
Focused Backend Tests for System Statistics Date-Range Support & Case Details Audit.
Covers:
1. Single day range (00:00:00 to 23:59:59 included)
2. Multi-day range (before excluded, start included, middle included, end included, after excluded)
3. Month boundary range (Aug 28 -> Sep 3)
4. Year boundary range (Dec 29 -> Jan 3)
5. Invalid reversed range (rejected with HTTP 400)
6. Valid range with no data (clean empty 200 response)
7. Cyber cell isolation with date range
8. Case Details audit (crime_type null safety, required fields, column intact)
"""
from uuid import uuid4
from datetime import date, datetime, timedelta, timezone
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
from models.cbir_result import CBIRResult
from models.case_timeline import CaseTimeline
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.possible_entity import PossibleEntity
from models.evidence_link import EvidenceLink
from models.report_record import ReportRecord

from services.admin_system_statistics_service import AdminSystemStatisticsService
from routes.admin_system_statistics_routes import (
    validate_date_range,
    get_system_statistics_summary,
    get_epra_statistics,
    get_cbir_statistics,
    get_investigator_statistics,
    get_case_trends,
    get_priority_analysis,
    get_forensic_summary,
)
from services.case_details_service import get_aggregated_case_details, get_case_basic_information


@pytest.fixture(scope="module")
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture(scope="module")
def stats_setup(db: Session):
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

    # Ensure City exists
    city = db.query(City).first()
    if not city:
        city = City(city_name=f"City_{suffix}")
        db.add(city)
        db.flush()
    city_id = city.id
    db.commit()

    # Create dedicated CyberCells
    cell1 = CyberCell(
        cyber_cell_name=f"Stats Cell 1 {suffix}",
        admin_email=f"admin_cell1_{suffix}@deps.local",
        city_id=city_id
    )
    cell2 = CyberCell(
        cyber_cell_name=f"Stats Cell 2 {suffix}",
        admin_email=f"admin_cell2_{suffix}@deps.local",
        city_id=city_id
    )
    db.add_all([cell1, cell2])
    db.flush()
    cell1_id = cell1.id
    cell2_id = cell2.id

    # Create Users
    admin_cell1 = User(
        full_name=f"Admin Cell1 {suffix}",
        username=f"admin_c1_{suffix}",
        email=f"admin_c1_{suffix}@deps.local",
        phone_number="1234567811",
        password="hashed_pw",
        role_id=1,
        cyber_cell_id=cell1_id,
        is_first_login=False,
        is_active=True
    )
    admin_cell2 = User(
        full_name=f"Admin Cell2 {suffix}",
        username=f"admin_c2_{suffix}",
        email=f"admin_c2_{suffix}@deps.local",
        phone_number="1234567812",
        password="hashed_pw",
        role_id=1,
        cyber_cell_id=cell2_id,
        is_first_login=False,
        is_active=True
    )
    inv_user = User(
        full_name=f"Investigator {suffix}",
        username=f"inv_{suffix}",
        email=f"inv_{suffix}@deps.local",
        phone_number="1234567813",
        password="hashed_pw",
        role_id=2,
        cyber_cell_id=cell1_id,
        is_first_login=False,
        is_active=True
    )
    ce_user = User(
        full_name=f"CyberExpert {suffix}",
        username=f"ce_{suffix}",
        email=f"ce_{suffix}@deps.local",
        phone_number="1234567814",
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

    # Create Cases with specific timestamps for boundary testing:
    # 1. Before range: 2026-09-09 23:59:59
    case_before = Case(
        case_id=f"C-BEF-{suffix}",
        title=f"Case Before {suffix}",
        crime_type="Cyber Fraud",
        priority="Low",
        status="Open",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=datetime(2026, 9, 9, 23, 59, 59)
    )
    # 2. Start date: 2026-09-10 00:00:00
    case_start = Case(
        case_id=f"C-STA-{suffix}",
        title=f"Case Start {suffix}",
        crime_type="Ransomware",
        priority="Medium",
        status="In Progress",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=datetime(2026, 9, 10, 0, 0, 0)
    )
    # 3. Middle date: 2026-09-15 12:00:00
    case_middle = Case(
        case_id=f"C-MID-{suffix}",
        title=f"Case Middle {suffix}",
        crime_type="Identity Theft",
        priority="High",
        status="Closed",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=datetime(2026, 9, 15, 12, 0, 0)
    )
    # 4. End date (late night): 2026-09-19 23:59:59
    case_end = Case(
        case_id=f"C-END-{suffix}",
        title=f"Case End {suffix}",
        crime_type="Financial Fraud",
        priority="Critical",
        status="Closed",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=datetime(2026, 9, 19, 23, 59, 59)
    )
    # 5. After range: 2026-09-20 00:00:01
    case_after = Case(
        case_id=f"C-AFT-{suffix}",
        title=f"Case After {suffix}",
        crime_type="Hacking",
        priority="High",
        status="Open",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=datetime(2026, 9, 20, 0, 0, 1)
    )
    # 6. Month boundary: 2026-08-31 15:00:00
    case_month_boundary = Case(
        case_id=f"C-MBD-{suffix}",
        title=f"Case Month Boundary {suffix}",
        crime_type="Cyber Stalking",
        priority="Medium",
        status="In Progress",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=datetime(2026, 8, 31, 15, 0, 0)
    )
    # 7. Year boundary: 2025-12-31 22:00:00
    case_year_boundary = Case(
        case_id=f"C-YBD-{suffix}",
        title=f"Case Year Boundary {suffix}",
        crime_type="Data Breach",
        priority="High",
        status="Open",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        created_at=datetime(2025, 12, 31, 22, 0, 0)
    )
    # 8. Case in Cell 2 (isolated) at 2026-09-15 12:00:00
    case_cell2 = Case(
        case_id=f"C-CL2-{suffix}",
        title=f"Case Cell 2 {suffix}",
        crime_type="Malware",
        priority="High",
        status="Open",
        created_by=admin_c2_id,
        created_at=datetime(2026, 9, 15, 12, 0, 0)
    )
    # 9. Case with NULL crime_type for Task 2 audit
    case_null_crime = Case(
        case_id=f"C-NUL-{suffix}",
        title=f"Case Null Crime {suffix}",
        crime_type=None,
        priority="Medium",
        status="Open",
        created_by=admin_c1_id,
        investigator_id=inv_id,
        cyber_expert_id=ce_id,
        description="Case where crime_type is null",
        created_at=datetime(2026, 9, 15, 12, 0, 0)
    )

    db.add_all([
        case_before, case_start, case_middle, case_end, case_after,
        case_month_boundary, case_year_boundary, case_cell2, case_null_crime
    ])
    db.flush()

    case_ids = [
        case_before.id, case_start.id, case_middle.id, case_end.id, case_after.id,
        case_month_boundary.id, case_year_boundary.id, case_cell2.id, case_null_crime.id
    ]

    # Evidence & child forensic records
    ev_mid = Evidence(
        evidence_id=f"EV-MID-{suffix}",
        case_id=case_middle.id,
        file_name="mid.jpg",
        file_type="image/jpeg",
        file_size=1024,
        file_path="/mid.jpg",
        status="Active",
        created_at=datetime(2026, 9, 15, 12, 0, 0)
    )
    ev_end = Evidence(
        evidence_id=f"EV-END-{suffix}",
        case_id=case_end.id,
        file_name="end.jpg",
        file_type="image/jpeg",
        file_size=2048,
        file_path="/end.jpg",
        status="Active",
        created_at=datetime(2026, 9, 19, 23, 0, 0)
    )
    ev_after = Evidence(
        evidence_id=f"EV-AFTER-{suffix}",
        case_id=case_after.id,
        file_name="after.jpg",
        file_type="image/jpeg",
        file_size=1024,
        file_path="/after.jpg",
        status="Active",
        created_at=datetime(2026, 9, 20, 1, 0, 0)
    )
    db.add_all([ev_mid, ev_end, ev_after])
    db.flush()

    # EPRA results
    epra_mid = EPRAResult(
        case_id=case_middle.id,
        evidence_id=ev_mid.id,
        epra_score=85.0,
        priority="HIGH",
        analysis_status="COMPLETE",
        created_at=datetime(2026, 9, 15, 12, 30, 0),
        processed_at=datetime(2026, 9, 15, 12, 30, 0)
    )
    epra_end = EPRAResult(
        case_id=case_end.id,
        evidence_id=ev_end.id,
        epra_score=95.0,
        priority="CRITICAL",
        analysis_status="COMPLETE",
        created_at=datetime(2026, 9, 19, 23, 30, 0),
        processed_at=datetime(2026, 9, 19, 23, 30, 0)
    )
    epra_after = EPRAResult(
        case_id=case_after.id,
        evidence_id=ev_after.id,
        epra_score=50.0,
        priority="MEDIUM",
        analysis_status="COMPLETE",
        created_at=datetime(2026, 9, 20, 1, 30, 0),
        processed_at=datetime(2026, 9, 20, 1, 30, 0)
    )
    db.add_all([epra_mid, epra_end, epra_after])

    # CBIR result
    cbir_mid = CBIRResult(
        case_id=case_middle.id,
        query_evidence_id=ev_mid.id,
        candidate_evidence_id=ev_end.id,
        visual_similarity_score=0.91,
        semantic_score=0.90,
        sha256_exact_duplicate=False,
        classification="Very Strong Visual Match",
        confidence_level="High",
        recommendation="VERIFY",
        reason="Match",
        rank=1,
        created_at=datetime(2026, 9, 15, 13, 0, 0)
    )
    cbir_after = CBIRResult(
        case_id=case_after.id,
        query_evidence_id=ev_after.id,
        candidate_evidence_id=ev_mid.id,
        visual_similarity_score=0.88,
        semantic_score=0.85,
        sha256_exact_duplicate=False,
        classification="Strong Visual Match",
        confidence_level="High",
        recommendation="VERIFY",
        reason="Match",
        rank=1,
        created_at=datetime(2026, 9, 20, 2, 0, 0)
    )
    db.add_all([cbir_mid, cbir_after])

    # Forensic summary records
    h_mid = EvidenceHash(
        evidence_id=ev_mid.id,
        file_name="mid.jpg",
        sha256_hash="hash_mid",
        current_hash="hash_mid",
        hash_match=True,
        tampered=False,
        created_at=datetime(2026, 9, 15, 12, 0, 0)
    )
    m_mid = EvidenceRecord(
        case_id=str(case_middle.id),
        original_filename="mid.jpg",
        stored_filename="mid_stored.jpg",
        file_path="/mid.jpg",
        processing_status="PROCESSED",
        created_at=datetime(2026, 9, 15, 12, 0, 0)
    )
    pe_mid = PossibleEntity(
        case_id=case_middle.id,
        suspect_id=f"SUSP-MID-{suffix}",
        suspect_name="Suspect Mid",
        entity_type="EMAIL",
        rank=1,
        total_epra_score=85.0,
        created_at=datetime(2026, 9, 15, 12, 0, 0)
    )
    el_mid = EvidenceLink(
        case_id=case_middle.id,
        evidence_id=ev_mid.id,
        relationship_type="MANUAL_LINK",
        created_at=datetime(2026, 9, 15, 12, 0, 0)
    )
    rep_mid = ReportRecord(
        id=f"REP-MID-{suffix}",
        case_id=str(case_middle.case_id),
        investigator_name=inv_user.full_name,
        file_path="/rep_mid.pdf",
        file_name="rep_mid.pdf",
        generated_at=datetime(2026, 9, 15, 14, 0, 0)
    )
    db.add_all([h_mid, m_mid, pe_mid, el_mid, rep_mid])
    db.commit()

    data = {
        "suffix": suffix,
        "admin_cell1": admin_cell1,
        "admin_cell2": admin_cell2,
        "inv_user": inv_user,
        "ce_user": ce_user,
        "case_null_crime": case_null_crime,
        "case_middle": case_middle,
        "case_end": case_end,
        "case_cell2": case_cell2,
        "cell1_id": cell1_id,
        "cell2_id": cell2_id,
        "case_ids": case_ids
    }

    try:
        yield data
    finally:
        try:
            db.query(ReportRecord).filter(ReportRecord.id == f"REP-MID-{suffix}").delete(synchronize_session=False)
            db.query(EvidenceLink).filter(EvidenceLink.case_id.in_(case_ids)).delete(synchronize_session=False)
            db.query(PossibleEntity).filter(PossibleEntity.case_id.in_(case_ids)).delete(synchronize_session=False)
            db.query(EvidenceRecord).filter(EvidenceRecord.case_id.in_([str(cid) for cid in case_ids])).delete(synchronize_session=False)
            db.query(EvidenceHash).filter(EvidenceHash.evidence_id.in_([ev_mid.id, ev_end.id, ev_after.id])).delete(synchronize_session=False)
            db.query(CBIRResult).filter(CBIRResult.case_id.in_(case_ids)).delete(synchronize_session=False)
            db.query(EPRAResult).filter(EPRAResult.case_id.in_(case_ids)).delete(synchronize_session=False)
            db.query(Evidence).filter(Evidence.case_id.in_(case_ids)).delete(synchronize_session=False)
            db.query(Case).filter(Case.id.in_(case_ids)).delete(synchronize_session=False)
            db.query(User).filter(User.id.in_([admin_c1_id, admin_c2_id, inv_id, ce_id])).delete(synchronize_session=False)
            db.query(CyberCell).filter(CyberCell.id.in_([cell1_id, cell2_id])).delete(synchronize_session=False)
            db.commit()
        except Exception:
            db.rollback()


# ==============================================================================
# 1. TEST A: SINGLE DAY RANGE
# ==============================================================================

def test_single_day_range(db, stats_setup):
    """
    start_date = 2026-09-19, end_date = 2026-09-19
    Verify records throughout that full day (including 23:59:59) are included.
    Records from 2026-09-18 and 2026-09-20 are excluded.
    """
    admin = stats_setup["admin_cell1"]
    d = date(2026, 9, 19)

    summary = get_system_statistics_summary(
        dates=(d, d),
        current_user=admin,
        db=db
    )
    # case_end (created at 2026-09-19 23:59:59) must be included!
    assert summary.total_cases == 1
    assert summary.closed_cases == 1
    assert summary.active_cases == 0

    epra = get_epra_statistics(
        dates=(d, d),
        current_user=admin,
        db=db
    )
    # ev_end (analyzed at 2026-09-19 23:30:00) must be included!
    assert epra.total_evidence == 1
    assert epra.completed_analysis == 1
    assert epra.priority_distribution["CRITICAL"] == 1


# ==============================================================================
# 2. TEST B: MULTI-DAY RANGE (10 Sep -> 19 Sep)
# ==============================================================================

def test_multi_day_range(db, stats_setup):
    """
    start_date = 2026-09-10, end_date = 2026-09-19
    Verify:
    - before start excluded (case_before @ Sep 9 23:59:59)
    - start date included (case_start @ Sep 10 00:00:00)
    - middle included (case_middle @ Sep 15 12:00:00, case_null_crime @ Sep 15 12:00:00)
    - end date included (case_end @ Sep 19 23:59:59)
    - after end excluded (case_after @ Sep 20 00:00:01)
    Total matching cases in Cell 1: 4 (start, mid, null_crime, end)
    """
    admin = stats_setup["admin_cell1"]
    s = date(2026, 9, 10)
    e = date(2026, 9, 19)

    summary = get_system_statistics_summary(
        dates=(s, e),
        current_user=admin,
        db=db
    )
    assert summary.total_cases == 4
    # Closed cases: case_middle, case_end -> 2
    assert summary.closed_cases == 2
    # Active cases: case_start, case_null_crime -> 2
    assert summary.active_cases == 2

    cbir = get_cbir_statistics(
        dates=(s, e),
        current_user=admin,
        db=db
    )
    # cbir_mid was at Sep 15, cbir_after was at Sep 20
    assert cbir.total_comparisons == 1
    assert cbir.visual_matches == 1

    inv = get_investigator_statistics(
        dates=(s, e),
        current_user=admin,
        db=db
    )
    inv_item = next(i for i in inv.investigators if i.investigator_id == stats_setup["inv_user"].id)
    assert inv_item.assigned_cases == 4
    assert inv_item.completed_cases == 2
    assert inv_item.active_cases == 2
    assert inv_item.completion_ratio == 50.0

    forensic = get_forensic_summary(
        dates=(s, e),
        current_user=admin,
        db=db
    )
    assert forensic.integrity_verified == 1
    assert forensic.metadata_processed == 1
    assert forensic.suspect_entities_count == 1
    assert forensic.total_evidence_links == 1
    assert forensic.reports_generated == 1


# ==============================================================================
# 3. TEST C: MONTH BOUNDARY (28 Aug -> 03 Sep)
# ==============================================================================

def test_month_boundary_range(db, stats_setup):
    """
    start_date = 2026-08-28, end_date = 2026-09-03
    Includes case_month_boundary (created 2026-08-31 15:00:00).
    Excludes case_before (2026-09-09) and later cases.
    """
    admin = stats_setup["admin_cell1"]
    s = date(2026, 8, 28)
    e = date(2026, 9, 3)

    summary = get_system_statistics_summary(
        dates=(s, e),
        current_user=admin,
        db=db
    )
    assert summary.total_cases == 1
    assert summary.active_cases == 1
    assert summary.closed_cases == 0


# ==============================================================================
# 4. TEST D: YEAR BOUNDARY (29 Dec -> 03 Jan)
# ==============================================================================

def test_year_boundary_range(db, stats_setup):
    """
    start_date = 2025-12-29, end_date = 2026-01-03
    Includes case_year_boundary (created 2025-12-31 22:00:00).
    Excludes 2026-08 and 2026-09 cases.
    """
    admin = stats_setup["admin_cell1"]
    s = date(2025, 12, 29)
    e = date(2026, 1, 3)

    summary = get_system_statistics_summary(
        dates=(s, e),
        current_user=admin,
        db=db
    )
    assert summary.total_cases == 1
    assert summary.active_cases == 1
    assert summary.closed_cases == 0


# ==============================================================================
# 5. TEST E: INVALID REVERSED RANGE REJECTION
# ==============================================================================

def test_reversed_date_range_rejection(db, stats_setup):
    """
    start_date = 2026-09-19, end_date = 2026-09-10
    Must be rejected with HTTP 400 Bad Request.
    """
    # 1. Route-level validator
    with pytest.raises(HTTPException) as exc_route:
        validate_date_range(start_date=date(2026, 9, 19), end_date=date(2026, 9, 10))
    assert exc_route.value.status_code == 400
    assert "start_date must be before or equal to end_date" in str(exc_route.value.detail)

    # 2. Service-level defensive check
    with pytest.raises(HTTPException) as exc_service:
        AdminSystemStatisticsService.get_system_statistics_summary(
            db=db,
            current_user=stats_setup["admin_cell1"],
            start_date=date(2026, 9, 19),
            end_date=date(2026, 9, 10)
        )
    assert exc_service.value.status_code == 400
    assert "start_date must be before or equal to end_date" in str(exc_service.value.detail)


# ==============================================================================
# 6. TEST F: VALID RANGE WITH NO DATA (CLEAN EMPTY HTTP 200)
# ==============================================================================

def test_valid_range_with_no_data(db, stats_setup):
    """
    start_date = 2020-01-01, end_date = 2020-01-05
    Must return HTTP 200 with clean zero/empty structure (no 500 error).
    """
    admin = stats_setup["admin_cell1"]
    s = date(2020, 1, 1)
    e = date(2020, 1, 5)

    summary = get_system_statistics_summary(dates=(s, e), current_user=admin, db=db)
    assert summary.total_cases == 0
    assert summary.closed_cases == 0
    assert summary.active_cases == 0
    assert summary.total_evidence == 0
    assert summary.epra_coverage_percentage == 0.0
    assert summary.cbir_total_comparisons == 0

    epra = get_epra_statistics(dates=(s, e), current_user=admin, db=db)
    assert epra.total_evidence == 0
    assert epra.coverage_percentage == 0.0
    assert epra.average_epra_score is None

    cbir = get_cbir_statistics(dates=(s, e), current_user=admin, db=db)
    assert cbir.total_comparisons == 0
    assert cbir.visual_matches == 0
    assert cbir.match_rate == 0.0


# ==============================================================================
# 7. TEST G: CYBER CELL ISOLATION WITH DATE RANGE
# ==============================================================================

def test_cyber_cell_isolation_with_date_range(db, stats_setup):
    """
    case_cell2 was created at 2026-09-15 12:00:00 (inside the range).
    Verify that admin_cell1 NEVER receives case_cell2 data.
    """
    admin1 = stats_setup["admin_cell1"]
    admin2 = stats_setup["admin_cell2"]
    s = date(2026, 9, 10)
    e = date(2026, 9, 19)

    summary1 = get_system_statistics_summary(dates=(s, e), current_user=admin1, db=db)
    summary2 = get_system_statistics_summary(dates=(s, e), current_user=admin2, db=db)

    # Admin 1 sees only Cell 1 cases (4 cases)
    assert summary1.total_cases == 4

    # Admin 2 sees only Cell 2 case (1 case)
    assert summary2.total_cases == 1


# ==============================================================================
# 8. TEST H: CASE DETAILS AUDIT (TASK 2)
# ==============================================================================

def test_case_details_crime_type_audit(db, stats_setup):
    """
    Audit Cyber Expert -> Case Details regarding crime_type:
    1. Endpoint returns genuine Basic Information (Case ID, Name, Priority, Status, Assigned Date, Assigned By, Description).
    2. crime_type = None does NOT break the endpoint (schema has crime_type: Optional[str] = None).
    3. crime_type column is NOT removed from database or backend.
    4. Confirms: BACKEND CORRECT — FRONTEND FOLLOW-UP REQUIRED TO HIDE CRIME TYPE ROW.
    """
    ce = stats_setup["ce_user"]
    case_null = stats_setup["case_null_crime"]
    case_mid = stats_setup["case_middle"]

    # 1. Case with crime_type = None
    details_null = get_aggregated_case_details(db, str(case_null.case_id), ce)
    basic_null = details_null["basic_information"]
    assert basic_null["case_id"] == case_null.case_id
    assert basic_null["case_name"] == case_null.title
    assert basic_null["crime_type"] is None  # Safely returns None without error!
    assert basic_null["priority"] == case_null.priority
    assert basic_null["status"] == case_null.status
    assert basic_null["assigned_date"] is not None
    assert basic_null["assigned_by"] == stats_setup["admin_cell1"].full_name
    assert basic_null["description"] == case_null.description

    # 2. Case with existing crime_type
    details_mid = get_aggregated_case_details(db, str(case_mid.case_id), ce)
    basic_mid = details_mid["basic_information"]
    assert basic_mid["crime_type"] == "Identity Theft"
    assert basic_mid["priority"] == "High"
    assert basic_mid["status"] == "Closed"

    # 3. Verify Case model still has crime_type column
    assert hasattr(Case, "crime_type"), "crime_type MUST remain on Case model"
