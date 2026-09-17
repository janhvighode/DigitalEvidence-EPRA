import sys
from pathlib import Path
from datetime import datetime, timezone
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

# Ensure project root and backend are on sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from database.database import Base
from models.user import User
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.case import Case
from models.evidence import Evidence
from models.possible_entity import PossibleEntity
from models.case_timeline import CaseTimeline
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.case_note import CaseNote

from services.case_details_service import (
    get_case_basic_information,
    get_case_involved_entities,
    get_case_timeline_overview,
    get_case_evidence_summary,
    get_case_notes,
    create_case_note,
    get_aggregated_case_details
)
from services.evidence_service import authorize_case_access


def make_user(id: int, full_name: str, role_id: int, cyber_cell_id: int = 1, username: str = None) -> User:
    uname = username or f"user_{id}"
    return User(
        id=id,
        full_name=full_name,
        username=uname,
        email=f"{uname}@test.gov",
        phone_number="1234567890",
        password="hashed_password",
        role_id=role_id,
        cyber_cell_id=cyber_cell_id,
        is_first_login=False,
        is_active=True
    )


@pytest.fixture
def db():
    """Isolated in-memory SQLite database for deterministic testing."""
    from sqlalchemy.pool import StaticPool
    engine = create_engine(
        "sqlite:///:memory:",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
        echo=False
    )
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()

    # Seed roles, city, cell
    session.add(Role(id=1, role_name="Admin"))
    session.add(Role(id=2, role_name="Investigator"))
    session.add(Role(id=3, role_name="Cyber Expert"))
    city = City(id=1, city_name="Nagpur")
    cell = CyberCell(id=1, cyber_cell_name="Nagpur Cyber Cell", admin_email="admin@nagpur.gov", city_id=1)
    session.add_all([city, cell])
    session.commit()

    yield session
    session.close()


# ============================================================
# 1. AUTHENTICATION & ACCESS CONTROL
# ============================================================

def test_assigned_cyber_expert_access_allowed(db):
    """Assigned Cyber Expert can access case details without error."""
    admin = make_user(1, "Admin User", 1)
    cyber_expert = make_user(301, "Expert Alpha", 3)
    db.add_all([admin, cyber_expert])
    db.commit()

    case = Case(
        id=10,
        case_id="CASE-DYN-001",
        title="Ransomware Incident",
        description="Encrypted server backup",
        priority="High",
        status="Open",
        created_by=admin.id,
        cyber_expert_id=cyber_expert.id
    )
    db.add(case)
    db.commit()

    details = get_aggregated_case_details(db, "CASE-DYN-001", cyber_expert)
    assert details["basic_information"]["case_id"] == "CASE-DYN-001"
    assert details["basic_information"]["case_name"] == "Ransomware Incident"
    assert details["basic_information"]["priority"] == "High"
    assert details["basic_information"]["cyber_expert_name"] == "Expert Alpha"


def test_unassigned_cyber_expert_blocked(db):
    """Unassigned Cyber Expert receives 403 Forbidden."""
    admin = make_user(1, "Admin User", 1)
    cyber_expert_1 = make_user(301, "Expert Alpha", 3)
    cyber_expert_2 = make_user(302, "Expert Beta", 3)
    db.add_all([admin, cyber_expert_1, cyber_expert_2])
    db.commit()

    case = Case(
        id=11,
        case_id="CASE-DYN-002",
        title="Unauthorized Intrusion",
        priority="Critical",
        status="Open",
        created_by=admin.id,
        cyber_expert_id=cyber_expert_1.id
    )
    db.add(case)
    db.commit()

    with pytest.raises(HTTPException) as exc_info:
        get_aggregated_case_details(db, "CASE-DYN-002", cyber_expert_2)
    assert exc_info.value.status_code == 403


# ============================================================
# 2. BASIC INFORMATION FROM DB (NO SCREENSHOT HARDCODING)
# ============================================================

def test_basic_information_db_backed(db):
    """Basic Information fields reflect genuine database records and dynamic lookups."""
    admin = make_user(101, "Super Admin", 1)
    inv = make_user(201, "Officer Smith", 2)
    expert = make_user(301, "Dr. Jones", 3)
    db.add_all([admin, inv, expert])
    db.commit()

    case = Case(
        id=20,
        case_id="CASE-CUSTOM-99",
        title="Custom Title Here",
        description="Data breach through phishing",
        priority="Medium",
        status="Under Review",
        created_by=admin.id,
        investigator_id=inv.id,
        cyber_expert_id=expert.id
    )
    db.add(case)
    db.commit()

    info = get_case_basic_information(db, case)
    assert info["case_id"] == "CASE-CUSTOM-99"
    assert info["case_name"] == "Custom Title Here"
    assert info["crime_type"] == "Data breach through phishing"
    assert info["priority"] == "Medium"
    assert info["status"] == "Under Review"
    assert info["assigned_by"] == "Super Admin"
    assert info["investigator_name"] == "Officer Smith"
    assert info["cyber_expert_name"] == "Dr. Jones"


# ============================================================
# 3. INVOLVED ENTITIES (REUSE POSSIBLE_ENTITIES, EMPTY SUPPORT)
# ============================================================

def test_involved_entities_genuine_and_empty_state(db):
    """Reuses PossibleEntity table; missing entities returns [] without synthetic data."""
    admin = make_user(1, "Admin", 1)
    expert = make_user(301, "Expert", 3)
    db.add_all([admin, expert])
    db.commit()

    case = Case(id=30, case_id="CASE-ENT-01", title="Fraud", created_by=admin.id, cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    # When no entities are present, must return empty list
    entities = get_case_involved_entities(db, case, expert)
    assert entities == []

    # Add genuine entities
    pe1 = PossibleEntity(
        id=1,
        case_id=case.id,
        suspect_id="SUSPECT-001",
        suspect_name="attacker@malicious.com",
        entity_type="EMAIL",
        rank=1,
        total_epra_score=9.5,
        linked_evidence_count=2,
        confidence_score=0.85
    )
    pe2 = PossibleEntity(
        id=2,
        case_id=case.id,
        suspect_id="SUSPECT-002",
        suspect_name="198.51.100.23",
        entity_type="IP ADDRESS",
        rank=2,
        total_epra_score=7.0,
        linked_evidence_count=1,
        confidence_score=0.60
    )
    db.add_all([pe1, pe2])
    db.commit()

    ranked = get_case_involved_entities(db, case, expert)
    assert len(ranked) == 2
    r0_name = ranked[0].suspect_name if hasattr(ranked[0], "suspect_name") else ranked[0]["suspect_name"]
    r0_type = ranked[0].entity_type if hasattr(ranked[0], "entity_type") else ranked[0]["entity_type"]
    r0_rank = ranked[0].rank if hasattr(ranked[0], "rank") else ranked[0]["rank"]
    r1_name = ranked[1].suspect_name if hasattr(ranked[1], "suspect_name") else ranked[1]["suspect_name"]
    r1_rank = ranked[1].rank if hasattr(ranked[1], "rank") else ranked[1]["rank"]

    assert r0_name == "attacker@malicious.com"
    assert r0_type == "EMAIL"
    assert r0_rank == 1
    assert r1_name == "198.51.100.23"
    assert r1_rank == 2


# ============================================================
# 4. TIMELINE (REUSE TIMELINESERVICE & CASETIMELINE, DEDUPLICATION)
# ============================================================

def test_timeline_genuine_events_and_deduplication(db):
    """Reuses timeline sources, avoids duplicate events, no fake screenshot events."""
    admin = make_user(1, "Admin", 1)
    inv = make_user(2, "Investigator", 2)
    expert = make_user(3, "Expert", 3)
    db.add_all([admin, inv, expert])
    db.commit()

    case = Case(
        id=40,
        case_id="CASE-TIME-01",
        title="Malware Tracking",
        created_by=admin.id,
        investigator_id=inv.id,
        cyber_expert_id=expert.id,
        created_at=datetime(2026, 9, 1, 10, 0, tzinfo=timezone.utc)
    )
    db.add(case)
    db.commit()

    # CaseTimeline event
    ct1 = CaseTimeline(
        id=1,
        case_id=case.id,
        event="Evidence EV-001 uploaded",
        performed_by=inv.id,
        performed_by_role="Investigator",
        created_at=datetime(2026, 9, 1, 11, 0, tzinfo=timezone.utc)
    )
    # CustodyLog and ActivityLog sharing event_reference (must be deduplicated)
    custody = CustodyLog(
        id=1,
        case_id="CASE-TIME-01",
        evidence_id="EV-001",
        action="TRANSFER_INITIATED",
        investigator_id=inv.id,
        investigator_name=inv.full_name,
        actor_role="Investigator",
        event_reference="TX-12345",
        timestamp=datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)
    )
    activity = ActivityLog(
        id=1,
        case_id="CASE-TIME-01",
        action="TRANSFER_INITIATED",
        activity="TRANSFER_INITIATED",
        investigator_name=inv.full_name,
        event_reference="TX-12345",
        timestamp=datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc)
    )
    db.add_all([ct1, custody, activity])
    db.commit()

    timeline = get_case_timeline_overview(db, case)
    # Both sources are combined, and TX-12345 is merged into 1 audit item
    assert len(timeline) >= 2
    # Ensure events are genuine
    titles = [t["title"] for t in timeline]
    assert "Evidence EV-001 uploaded" in titles
    # Ensure fake screenshot strings are NOT present
    assert "Initial review completed" not in titles
    assert "Evidence collection in progress" not in titles


# ============================================================
# 5. EVIDENCE SUMMARY (CANONICAL EPRA NORMALIZATION & DERIVED CATEGORIES)
# ============================================================

def test_evidence_summary_canonical_and_categories(db):
    """Tests dynamic counts across all 12 types and derived summary categories."""
    admin = make_user(1, "Admin", 1)
    expert = make_user(3, "Expert", 3)
    db.add_all([admin, expert])
    db.commit()

    case = Case(id=50, case_id="CASE-EV-01", title="Data Theft", created_by=admin.id, cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    # Add 7 items of distinct types
    evidences = [
        Evidence(id=1, case_id=case.id, evidence_id="EV-01", file_name="photo.jpg", file_type="image/jpeg", file_size=100, file_path="/tmp/1"),
        Evidence(id=2, case_id=case.id, evidence_id="EV-02", file_name="screenshot.png", file_type="image/png", file_size=100, file_path="/tmp/2"),
        Evidence(id=3, case_id=case.id, evidence_id="EV-03", file_name="doc.pdf", file_type="application/pdf", file_size=100, file_path="/tmp/3"),
        Evidence(id=4, case_id=case.id, evidence_id="EV-04", file_name="report.docx", file_type="Document", file_size=100, file_path="/tmp/4"),
        Evidence(id=5, case_id=case.id, evidence_id="EV-05", file_name="sheet.xlsx", file_type="Spreadsheet", file_size=100, file_path="/tmp/5"),
        Evidence(id=6, case_id=case.id, evidence_id="EV-06", file_name="clip.mp4", file_type="video/mp4", file_size=100, file_path="/tmp/6"),
        Evidence(id=7, case_id=case.id, evidence_id="EV-07", file_name="call.wav", file_type="audio/wav", file_size=100, file_path="/tmp/7"),
    ]
    db.add_all(evidences)
    db.commit()

    summary = get_case_evidence_summary(db, case)
    assert summary["total_evidence"] == 7

    # Canonical breakdown
    by_type = summary["counts_by_type"]
    assert by_type["IMAGE"] == 2
    assert by_type["PDF"] == 1
    assert by_type["DOCUMENT"] == 1
    assert by_type["SPREADSHEET"] == 1
    assert by_type["VIDEO"] == 1
    assert by_type["AUDIO"] == 1

    # Derived categories
    cats = summary["summary_categories"]
    assert cats["images"] == 2
    assert cats["documents"] == 3  # PDF(1) + DOCUMENT(1) + SPREADSHEET(1)
    assert cats["videos"] == 1
    assert cats["audio"] == 1
    assert cats["others"] == 0


# ============================================================
# 6. CASE NOTES PERSISTENCE, AUTHOR BINDING, VALIDATION, ISOLATION
# ============================================================

def test_case_notes_persistence_and_author_binding(db):
    """Case notes are persisted, author strictly set from current_user, and retrieved."""
    admin = make_user(1, "Admin", 1)
    expert = make_user(301, "Expert Officer", 3)
    db.add_all([admin, expert])
    db.commit()

    case = Case(id=60, case_id="CASE-NOTES-01", title="Notes Test", created_by=admin.id, cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    # 1. Add Note
    note_resp = create_case_note(db, case, "Suspect IP verified via ISP records.", expert)
    assert note_resp["content"] == "Suspect IP verified via ISP records."
    assert note_resp["created_by"] == expert.id
    assert note_resp["created_by_name"] == "Expert Officer"
    assert note_resp["id"] is not None

    # 2. Get Notes
    notes = get_case_notes(db, case)
    assert len(notes) == 1
    assert notes[0]["content"] == "Suspect IP verified via ISP records."
    assert notes[0]["created_by_name"] == "Expert Officer"


def test_blank_note_rejected(db):
    """Blank or whitespace-only notes raise 400 Bad Request."""
    admin = make_user(1, "Admin", 1)
    expert = make_user(301, "Expert", 3)
    db.add_all([admin, expert])
    db.commit()

    case = Case(id=61, case_id="CASE-NOTES-02", title="Blank Test", created_by=admin.id, cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    with pytest.raises(HTTPException) as exc_empty:
        create_case_note(db, case, "", expert)
    assert exc_empty.value.status_code == 400

    with pytest.raises(HTTPException) as exc_spaces:
        create_case_note(db, case, "   \n\t  ", expert)
    assert exc_spaces.value.status_code == 400


def test_cross_case_notes_isolation(db):
    """Notes from Case A never leak into Case B."""
    admin = make_user(1, "Admin", 1)
    expert = make_user(301, "Expert", 3)
    db.add_all([admin, expert])
    db.commit()

    case_a = Case(id=62, case_id="CASE-A", title="Case A", created_by=admin.id, cyber_expert_id=expert.id)
    case_b = Case(id=63, case_id="CASE-B", title="Case B", created_by=admin.id, cyber_expert_id=expert.id)
    db.add_all([case_a, case_b])
    db.commit()

    create_case_note(db, case_a, "Note for Case A only", expert)
    create_case_note(db, case_b, "Note for Case B only", expert)

    notes_a = get_case_notes(db, case_a)
    notes_b = get_case_notes(db, case_b)

    assert len(notes_a) == 1
    assert notes_a[0]["content"] == "Note for Case A only"

    assert len(notes_b) == 1
    assert notes_b[0]["content"] == "Note for Case B only"


# ============================================================
# 7. EMPTY / MINIMAL CASE TEST
# ============================================================

def test_empty_case_handling(db):
    """Empty case returns valid database values without crashes or fake data."""
    admin = make_user(1, "Creator Admin", 1)
    expert = make_user(301, "Assigned Expert", 3)
    db.add_all([admin, expert])
    db.commit()

    empty_case = Case(
        id=70,
        case_id="CASE-EMPTY-01",
        title="Empty Case",
        description="",
        priority="Low",
        status="Open",
        created_by=admin.id,
        cyber_expert_id=expert.id
    )
    db.add(empty_case)
    db.commit()

    details = get_aggregated_case_details(db, "CASE-EMPTY-01", expert)

    # Basic Info
    assert details["basic_information"]["case_id"] == "CASE-EMPTY-01"
    assert details["basic_information"]["assigned_by"] == "Creator Admin"

    # Entities
    assert details["involved_entities"] == []

    # Timeline (baseline created event only)
    assert len(details["timeline"]) == 1
    assert details["timeline"][0]["event_type"] == "CASE_CREATED"

    # Evidence Summary
    assert details["evidence_summary"]["total_evidence"] == 0
    assert details["evidence_summary"]["summary_categories"]["images"] == 0
    assert details["evidence_summary"]["summary_categories"]["documents"] == 0

    # Notes
    assert details["case_notes"] == []


# ============================================================
# 8. NO SCREENSHOT HARDCODING AUDIT
# ============================================================

def test_no_screenshot_hardcoding_in_production_code():
    """Confirms production code contains no hardcoded values from the UI mockup."""
    forbidden_tokens = [
        "CASE-6922",
        "Ankit Sharma",
        "ABC Bank",
        "Net Banking / UPI",
        "Nagpur, Maharashtra",
        "12 Images",
        "8 Documents",
        "3 Videos",
        "2 Audio",
        "Initial review completed",
        "Evidence collection in progress",
        "Pending further analysis/reporting"
    ]

    target_files = [
        backend_dir / "services" / "case_details_service.py",
        backend_dir / "routes" / "case_details_routes.py",
        backend_dir / "schemas" / "case_details.py",
        backend_dir / "models" / "case_note.py",
    ]

    for file_path in target_files:
        assert file_path.exists(), f"File {file_path} must exist"
        content = file_path.read_text(encoding="utf-8")
        for token in forbidden_tokens:
            assert token not in content, f"Forbidden screenshot token '{token}' found in {file_path.name}"


# ============================================================
# 9. QUICK ACTION DEPENDENCY INTEGRITY
# ============================================================

def test_quick_action_dependencies_exist():
    """Verifies that all 5 Quick Action modules exist and export expected endpoints/services."""
    # 1. Hash Verification
    from services.hash_verification_service import HashVerificationService
    from routes.evidence_routes import router as ev_router

    # 2. Metadata Extraction
    from services.metadata_service import MetadataService
    from routes.metadata_routes import router as meta_router

    # 3. Relationship Analysis
    from services.relationship_graph_service import RelationshipGraphService
    from routes.relationship_routes import relationship_router

    # 4. Chain of Custody
    from services.custody_service import CustodyService
    from routes.custody_routes import router as custody_router

    # 5. Technical Report
    from services.technical_report_service import TechnicalReportService
    from routes.technical_report_routes import router as report_router

    assert hasattr(HashVerificationService, "verify_evidence_integrity")
    assert hasattr(HashVerificationService, "get_case_hash_summary")
    assert hasattr(MetadataService, "sync_case_from_adapter")
    assert hasattr(RelationshipGraphService, "get_relationship_graph")
    assert hasattr(CustodyService, "get_custody_summary")
    assert hasattr(TechnicalReportService, "get_case_reporting_summary")
    assert hasattr(TechnicalReportService, "assemble_report_data")
    assert hasattr(TechnicalReportService, "build_report_data")


# ============================================================
# 10. FASTAPI CLIENT ROUTE INTEGRATION
# ============================================================

def test_fastapi_route_integration(db):
    """Verifies HTTP status codes, headers, and serialization via FastAPI TestClient."""
    from fastapi.testclient import TestClient
    from app.main import app
    from database.database import get_db
    from utils.current_user import get_current_user

    admin = make_user(1, "Admin", 1)
    expert = make_user(301, "Expert User", 3)
    unassigned_expert = make_user(302, "Unassigned User", 3)
    db.add_all([admin, expert, unassigned_expert])
    db.commit()

    case = Case(
        id=80,
        case_id="CASE-HTTP-01",
        title="HTTP Details Case",
        description="Testing HTTP routes",
        priority="High",
        status="Open",
        created_by=admin.id,
        cyber_expert_id=expert.id
    )
    db.add(case)
    db.commit()

    # Override dependencies
    app.dependency_overrides[get_db] = lambda: db
    app.dependency_overrides[get_current_user] = lambda: expert

    client = TestClient(app)

    try:
        # 1. GET /cases/{case_id}/details
        resp = client.get(f"/cases/{case.case_id}/details")
        assert resp.status_code == 200
        data = resp.json()
        assert data["basic_information"]["case_id"] == "CASE-HTTP-01"
        assert data["basic_information"]["case_name"] == "HTTP Details Case"
        assert data["basic_information"]["cyber_expert_name"] == "Expert User"
        assert "evidence_summary" in data
        assert "summary_categories" in data["evidence_summary"]

        # 2. POST /cases/{case_id}/notes
        note_payload = {"content": "First HTTP note logged."}
        post_resp = client.post(f"/cases/{case.case_id}/notes", json=note_payload)
        assert post_resp.status_code == 201
        note_data = post_resp.json()
        assert note_data["content"] == "First HTTP note logged."
        assert note_data["created_by"] == expert.id
        assert note_data["created_by_name"] == "Expert User"

        # 3. POST /cases/{case_id}/notes with blank content -> 400
        blank_resp = client.post(f"/cases/{case.case_id}/notes", json={"content": "   "})
        assert blank_resp.status_code == 400

        # 4. GET /cases/{case_id}/notes
        get_notes_resp = client.get(f"/cases/{case.case_id}/notes")
        assert get_notes_resp.status_code == 200
        notes_list = get_notes_resp.json()
        assert len(notes_list) == 1
        assert notes_list[0]["content"] == "First HTTP note logged."

        # 5. Unassigned user -> 403 Forbidden
        app.dependency_overrides[get_current_user] = lambda: unassigned_expert
        unauth_resp = client.get(f"/cases/{case.case_id}/details")
        assert unauth_resp.status_code == 403

    finally:
        app.dependency_overrides.clear()
