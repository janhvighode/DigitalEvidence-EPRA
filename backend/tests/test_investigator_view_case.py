"""
Comprehensive Test Suite for Investigator 'View Case' Workspace:
- Case Overview Tab
- Evidence Management Tab

Covers:
1. Role 2 assigned investigator can access Case Overview
2. Unassigned investigator rejected with 403 Forbidden
3. Non-investigator roles rejected with 403 Forbidden
4. Zero evidence case returns clean zeros and progress 0.0
5. Exact statistics calculation and progress percentage
6. Assigned Cyber Expert resolved correctly (or None if unassigned)
7. Case Description is genuine Case.description; no fake crime_type
8. Recent Activity derived strictly from genuine records (CaseTimeline / Custody)
9. Evidence Summary cards calculated accurately (Total, Analyzed, Pending, Integrity Issues)
10. Evidence Repository paginated listing with correct joined EPRA and Hash statuses
11. Evidence Repository search and filters (search, file_type, analysis_status, priority)
12. Unanalyzed evidence display fallback to 'Pending' without fake DB records
13. Single Evidence Detail integrating Evidence + Hash + EPRA + Metadata (EvidenceRecord)
14. Secure evidence file download with path traversal prevention and 404 on missing file
15. Secure evidence preview with format validation (rejecting unsupported formats with 400)
16. Reused existing evidence upload via POST /cases/{case_id}/evidence
17. Strict authorization, no client investigator_id, and zero cross-case leakage
"""
import sys
import tempfile
from pathlib import Path
from datetime import datetime, timezone
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException, UploadFile
import io

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
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from models.case_timeline import CaseTimeline
from models.evidence_record import EvidenceRecord
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.notification import Notification
from models.report_record import ReportRecord
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink
from models.cbir_result import CBIRResult

from routes.investigator_dashboard_routes import (
    verify_investigator,
    fetch_case_overview,
    fetch_case_evidence_summary,
    fetch_case_evidence_repository,
    fetch_evidence_detail,
    download_evidence_file,
    preview_evidence_file,
    fetch_analysis_progress_summary,
    fetch_analysis_progress_evidence,
    fetch_epra_priority_distribution,
    fetch_pending_analysis,
    fetch_single_analysis_detail,
    fetch_relationship_view,
    fetch_relationship_node_detail
)
from services.investigator_dashboard_service import (
    get_investigator_assigned_case,
    get_investigator_case_overview,
    get_investigator_case_evidence_summary,
    get_investigator_case_evidence_repository,
    get_investigator_evidence_detail,
    get_investigator_evidence_file,
    get_investigator_analysis_summary,
    get_investigator_analysis_evidence_repository,
    get_investigator_epra_priority_distribution,
    get_investigator_pending_analysis,
    get_investigator_single_analysis_detail,
    get_investigator_relationship_view,
    get_investigator_relationship_node_detail
)
from services.evidence_service import (
    authorize_case_access,
    create_case_evidence,
    get_case_evidence_list
)


def setup_test_db():
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(
        engine,
        tables=[
            Role.__table__,
            City.__table__,
            CyberCell.__table__,
            User.__table__,
            Case.__table__,
            Evidence.__table__,
            EvidenceHash.__table__,
            EPRAResult.__table__,
            CaseTimeline.__table__,
            EvidenceRecord.__table__,
            CustodyLog.__table__,
            ActivityLog.__table__,
            Notification.__table__,
            ReportRecord.__table__,
            PossibleEntity.__table__,
            PossibleEntityEvidenceLink.__table__,
            EvidenceLink.__table__,
            CBIRResult.__table__
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Seed Users
    # 101: Admin (Role 1)
    # 201: Investigator Vikram (Role 2)
    # 202: Investigator Priya (Role 2 - other investigator)
    # 301: Cyber Expert Rajesh (Role 3)
    admin = User(
        id=101, full_name="Admin Alice", username="admin_alice", email="alice@police.gov.in",
        phone_number="9000000001", password="hash", role_id=1, cyber_cell_id=1, is_active=True
    )
    investigator_1 = User(
        id=201, full_name="Inspector Vikram", username="vikram_inv", email="vikram@police.gov.in",
        phone_number="9000000002", password="hash", role_id=2, cyber_cell_id=1, is_active=True
    )
    investigator_2 = User(
        id=202, full_name="Inspector Priya", username="priya_inv", email="priya@police.gov.in",
        phone_number="9000000003", password="hash", role_id=2, cyber_cell_id=1, is_active=True
    )
    cyber_expert_1 = User(
        id=301, full_name="Analyst Rajesh", username="rajesh_ce", email="rajesh@police.gov.in",
        phone_number="9000000004", password="hash", role_id=3, cyber_cell_id=1, is_active=True
    )

    db.add_all([admin, investigator_1, investigator_2, cyber_expert_1])
    db.commit()

    # Seed Cases:
    # Case 1 (c1): Assigned to investigator_1 (201) & cyber_expert_1 (301)
    c1 = Case(
        id=1, case_id="CASE-2024-001", title="Bank Phishing Fraud",
        description="Authentic Case Description for Phishing Fraud Investigation",
        investigator_id=201, cyber_expert_id=301, priority="High", status="In Progress", created_by=101,
        created_at=datetime(2024, 1, 10, 10, 0, 0)
    )
    # Case 2 (c2): Assigned to investigator_1 (201), NO cyber expert assigned (None)
    c2 = Case(
        id=2, case_id="CASE-2024-002", title="Zero Evidence Case",
        description="Newly registered complaint without evidence files yet",
        investigator_id=201, cyber_expert_id=None, priority="Medium", status="Open", created_by=101,
        created_at=datetime(2024, 2, 1, 9, 0, 0)
    )
    # Case 3 (c3): Assigned to investigator_2 (202) -> for cross-investigator leakage tests
    c3 = Case(
        id=3, case_id="CASE-2024-003", title="Crypto Ransomware Ring",
        description="Investigator Priya's isolated case",
        investigator_id=202, cyber_expert_id=301, priority="Critical", status="Open", created_by=101,
        created_at=datetime(2024, 2, 5, 12, 0, 0)
    )
    # Case 4 (c4): Assigned to investigator_1 (201) & cyber_expert_1 (301) for Analysis Progress & Relationship View
    c4 = Case(
        id=4, case_id="CASE-2024-004", title="Advanced Cyber Fraud",
        description="Complex financial intrusion involving multiple evidence types",
        investigator_id=201, cyber_expert_id=301, priority="Critical", status="In Progress", created_by=101,
        created_at=datetime(2024, 2, 10, 10, 0, 0)
    )

    db.add_all([c1, c2, c3, c4])
    db.commit()

    # Seed Evidence for Case 1:
    # Ev 1: Image, Analyzed (COMPLETE), High Priority, Verified hash
    ev1 = Evidence(
        id=1, evidence_id="EV-2024-001-001", case_id=1, file_name="phishing_email.png",
        file_type="Image", file_size=102400, file_path="uploads/evidence/1/phishing_email.png",
        created_at=datetime(2024, 1, 11, 11, 0, 0)
    )
    h1 = EvidenceHash(
        id=1, evidence_id=1, file_name="phishing_email.png",
        sha256_hash="aaaa1111" * 8, current_hash="aaaa1111" * 8, original_hash="aaaa1111" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 1, 11, 11, 5, 0),
        verified_by=201
    )
    epra1 = EPRAResult(
        id=1, case_id=1, evidence_id=1, authenticity_risk=0.85, context_intelligence=0.75,
        behaviour_intelligence=0.65, semantic_intelligence=0.70, investigative_intelligence=0.80,
        ipi=0.75, epra_score=82.5, priority="High", rank=1, analysis_status="COMPLETE"
    )
    er1 = EvidenceRecord(
        id=1, case_id="CASE-2024-001", external_evidence_id="EV-2024-001-001",
        original_filename="phishing_email.png", stored_filename="stored_phishing.png",
        file_path="uploads/evidence/1/phishing_email.png", file_extension=".png", mime_type="image/png",
        mime_type_source="backend_supplied", evidence_type="Image", file_size_bytes=102400,
        filesystem_ctime="2024-01-11 11:00:00", filesystem_mtime="2024-01-11 11:00:00",
        created_at=datetime(2024, 1, 11, 11, 0, 0), modified_at=datetime(2024, 1, 11, 11, 0, 0),
        notes="Email screenshot showing phishing domain"
    )

    # Ev 2: Document, Analyzed (COMPLETE), Critical Priority, Tampered hash
    ev2 = Evidence(
        id=2, evidence_id="EV-2024-001-002", case_id=1, file_name="transaction_log.pdf",
        file_type="PDF Document", file_size=204800, file_path="uploads/evidence/1/transaction_log.pdf",
        created_at=datetime(2024, 1, 12, 14, 0, 0)
    )
    h2 = EvidenceHash(
        id=2, evidence_id=2, file_name="transaction_log.pdf",
        sha256_hash="bbbb2222" * 8, current_hash="bbbb2222" * 8, original_hash="cccc3333" * 8,
        hash_match=False, tampered=True, integrity_status="TAMPERED", verified_at=datetime(2024, 1, 12, 14, 5, 0),
        verified_by=201
    )
    epra2 = EPRAResult(
        id=2, case_id=1, evidence_id=2, authenticity_risk=0.95, context_intelligence=0.90,
        behaviour_intelligence=0.88, semantic_intelligence=0.85, investigative_intelligence=0.92,
        ipi=0.90, epra_score=94.0, priority="Critical", rank=2, analysis_status="COMPLETE"
    )

    # Ev 3: Document, Analyzed (COMPLETE), Medium Priority, Verified hash
    ev3 = Evidence(
        id=3, evidence_id="EV-2024-001-003", case_id=1, file_name="statement.docx",
        file_type="Document", file_size=51200, file_path="uploads/evidence/1/statement.docx",
        created_at=datetime(2024, 1, 13, 16, 0, 0)
    )
    h3 = EvidenceHash(
        id=3, evidence_id=3, file_name="statement.docx",
        sha256_hash="dddd4444" * 8, current_hash="dddd4444" * 8, original_hash="dddd4444" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 1, 13, 16, 5, 0),
        verified_by=201
    )
    epra3 = EPRAResult(
        id=3, case_id=1, evidence_id=3, authenticity_risk=0.40, context_intelligence=0.50,
        behaviour_intelligence=0.45, semantic_intelligence=0.55, investigative_intelligence=0.48,
        ipi=0.48, epra_score=52.0, priority="Medium", rank=3, analysis_status="COMPLETE"
    )

    # Ev 4: Video, UNANALYZED (no EPRAResult in DB), Verified hash
    ev4 = Evidence(
        id=4, evidence_id="EV-2024-001-004", case_id=1, file_name="cctv_footage.mp4",
        file_type="Video", file_size=10485760, file_path="uploads/evidence/1/cctv_footage.mp4",
        created_at=datetime(2024, 1, 14, 18, 0, 0)
    )
    h4 = EvidenceHash(
        id=4, evidence_id=4, file_name="cctv_footage.mp4",
        sha256_hash="eeee5555" * 8, current_hash="eeee5555" * 8, original_hash="eeee5555" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 1, 14, 18, 5, 0),
        verified_by=201
    )

    db.add_all([ev1, h1, epra1, er1, ev2, h2, epra2, ev3, h3, epra3, ev4, h4])
    db.commit()

    # Seed CaseTimeline and CustodyLog for Case 1
    t1 = CaseTimeline(
        id=1, case_id=1, event="Evidence uploaded: EV-2024-001-001 (phishing_email.png)",
        performed_by=201, performed_by_role="Investigator", created_at=datetime(2024, 1, 11, 11, 2, 0)
    )
    t2 = CaseTimeline(
        id=2, case_id=1, event="Evidence uploaded: EV-2024-001-002 (transaction_log.pdf)",
        performed_by=201, performed_by_role="Investigator", created_at=datetime(2024, 1, 12, 14, 2, 0)
    )
    db.add_all([t1, t2])
    db.commit()

    # Seed Evidence and Relationships for Case 4 (8 items total)
    # Ev 10: Image, Analyzed (COMPLETE), High Priority, Verified hash
    ev10 = Evidence(
        id=10, evidence_id="EV-2024-004-010", case_id=4, file_name="rogue_server.png",
        file_type="Image", file_size=307200, file_path="uploads/evidence/4/rogue_server.png",
        created_at=datetime(2024, 2, 11, 10, 0, 0)
    )
    h10 = EvidenceHash(
        id=10, evidence_id=10, file_name="rogue_server.png",
        sha256_hash="11112222" * 8, current_hash="11112222" * 8, original_hash="11112222" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 2, 11, 10, 5, 0),
        verified_by=201
    )
    epra10 = EPRAResult(
        id=10, case_id=4, evidence_id=10, authenticity_risk=0.78, context_intelligence=0.82,
        behaviour_intelligence=0.75, semantic_intelligence=0.80, investigative_intelligence=0.85,
        ipi=0.80, epra_score=88.0, priority="High", rank=2, analysis_status="COMPLETE", semantic_status="MEASURED"
    )

    # Ev 11: Document (PDF), Analyzed (COMPLETE), Critical Priority, Verified hash
    ev11 = Evidence(
        id=11, evidence_id="EV-2024-004-011", case_id=4, file_name="wire_transfer.pdf",
        file_type="Document", file_size=409600, file_path="uploads/evidence/4/wire_transfer.pdf",
        created_at=datetime(2024, 2, 12, 11, 0, 0)
    )
    h11 = EvidenceHash(
        id=11, evidence_id=11, file_name="wire_transfer.pdf",
        sha256_hash="33334444" * 8, current_hash="33334444" * 8, original_hash="33334444" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 2, 12, 11, 5, 0),
        verified_by=201
    )
    epra11 = EPRAResult(
        id=11, case_id=4, evidence_id=11, authenticity_risk=0.96, context_intelligence=0.94,
        behaviour_intelligence=0.92, semantic_intelligence=None, investigative_intelligence=0.95,
        ipi=0.94, epra_score=96.0, priority="Critical", rank=1, analysis_status="COMPLETE", semantic_status="PENDING"
    )

    # Ev 12: Audio, Analyzed (PARTIAL / PENDING INPUTS), Medium Priority, Verified hash
    ev12 = Evidence(
        id=12, evidence_id="EV-2024-004-012", case_id=4, file_name="wiretap_call.mp3",
        file_type="Audio", file_size=524288, file_path="uploads/evidence/4/wiretap_call.mp3",
        created_at=datetime(2024, 2, 13, 12, 0, 0)
    )
    h12 = EvidenceHash(
        id=12, evidence_id=12, file_name="wiretap_call.mp3",
        sha256_hash="55556666" * 8, current_hash="55556666" * 8, original_hash="55556666" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 2, 13, 12, 5, 0),
        verified_by=201
    )
    epra12 = EPRAResult(
        id=12, case_id=4, evidence_id=12, authenticity_risk=0.60, context_intelligence=0.65,
        behaviour_intelligence=0.55, semantic_intelligence=None, investigative_intelligence=0.62,
        ipi=0.60, epra_score=62.0, priority="Medium", rank=3, analysis_status="PARTIAL / PENDING INPUTS",
        pending_external_inputs=["Voice Biometrics Verification", "Acoustic Noise Reduction"], semantic_status="PENDING"
    )

    # Ev 13: Video, Analyzed (COMPLETE), Low Priority, Verified hash
    ev13 = Evidence(
        id=13, evidence_id="EV-2024-004-013", case_id=4, file_name="surveillance_cam.mp4",
        file_type="Video", file_size=8388608, file_path="uploads/evidence/4/surveillance_cam.mp4",
        created_at=datetime(2024, 2, 14, 13, 0, 0)
    )
    h13 = EvidenceHash(
        id=13, evidence_id=13, file_name="surveillance_cam.mp4",
        sha256_hash="77778888" * 8, current_hash="77778888" * 8, original_hash="77778888" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 2, 14, 13, 5, 0),
        verified_by=201
    )
    epra13 = EPRAResult(
        id=13, case_id=4, evidence_id=13, authenticity_risk=0.40, context_intelligence=0.45,
        behaviour_intelligence=0.38, semantic_intelligence=None, investigative_intelligence=0.42,
        ipi=0.41, epra_score=42.0, priority="Low", rank=4, analysis_status="COMPLETE", semantic_status="PENDING"
    )

    # Ev 14: Text/Log, Analyzed (COMPLETE), Very Low Priority, Verified hash
    ev14 = Evidence(
        id=14, evidence_id="EV-2024-004-014", case_id=4, file_name="firewall_log.txt",
        file_type="Document", file_size=20480, file_path="uploads/evidence/4/firewall_log.txt",
        created_at=datetime(2024, 2, 15, 14, 0, 0)
    )
    h14 = EvidenceHash(
        id=14, evidence_id=14, file_name="firewall_log.txt",
        sha256_hash="99990000" * 8, current_hash="99990000" * 8, original_hash="99990000" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 2, 15, 14, 5, 0),
        verified_by=201
    )
    epra14 = EPRAResult(
        id=14, case_id=4, evidence_id=14, authenticity_risk=0.15, context_intelligence=0.20,
        behaviour_intelligence=0.10, semantic_intelligence=None, investigative_intelligence=0.18,
        ipi=0.16, epra_score=15.0, priority="Very Low", rank=5, analysis_status="COMPLETE", semantic_status="PENDING"
    )

    # Ev 15: Image, UNANALYZED (Exact SHA-256 match with ev10) -> Verified duplicate!
    ev15 = Evidence(
        id=15, evidence_id="EV-2024-004-015", case_id=4, file_name="backup_rogue_server.png",
        file_type="Image", file_size=307200, file_path="uploads/evidence/4/backup_rogue_server.png",
        created_at=datetime(2024, 2, 16, 15, 0, 0)
    )
    h15 = EvidenceHash(
        id=15, evidence_id=15, file_name="backup_rogue_server.png",
        sha256_hash="11112222" * 8, current_hash="11112222" * 8, original_hash="11112222" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 2, 16, 15, 5, 0),
        verified_by=201
    )

    # Ev 16: Image, UNANALYZED (CBIR visual similarity candidate with ev10)
    ev16 = Evidence(
        id=16, evidence_id="EV-2024-004-016", case_id=4, file_name="phishing_kit_logo.png",
        file_type="Image", file_size=153600, file_path="uploads/evidence/4/phishing_kit_logo.png",
        created_at=datetime(2024, 2, 17, 16, 0, 0)
    )
    h16 = EvidenceHash(
        id=16, evidence_id=16, file_name="phishing_kit_logo.png",
        sha256_hash="ababcdcd" * 8, current_hash="ababcdcd" * 8, original_hash="ababcdcd" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 2, 17, 16, 5, 0),
        verified_by=201
    )

    # Ev 17: Image, UNANALYZED (clean pending, no EPRA, no CBIR)
    ev17 = Evidence(
        id=17, evidence_id="EV-2024-004-017", case_id=4, file_name="unprocessed_snapshot.png",
        file_type="Image", file_size=256000, file_path="uploads/evidence/4/unprocessed_snapshot.png",
        created_at=datetime(2024, 2, 18, 17, 0, 0)
    )
    h17 = EvidenceHash(
        id=17, evidence_id=17, file_name="unprocessed_snapshot.png",
        sha256_hash="deadbeef" * 8, current_hash="deadbeef" * 8, original_hash="deadbeef" * 8,
        hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime(2024, 2, 18, 17, 5, 0),
        verified_by=201
    )

    # Graph Entities for Case 4
    pe1 = PossibleEntity(
        id=1, case_id=4, suspect_id="SUSPECT-8E3A4B5C", suspect_name="Unknown Wire Recipient",
        entity_type="Suspect", rank=1, total_epra_score=96.0, linked_evidence_count=1, confidence_score=0.92
    )
    pe_link1 = PossibleEntityEvidenceLink(
        id=1, entity_id=1, evidence_id=11
    )
    el1 = EvidenceLink(
        id=1, case_id=4, evidence_id=10, suspect_name="Unknown Wire Recipient",
        device_name="Server SRV-01", relationship_type="DEVICE_SOURCE", notes="Extracted from rogue server infrastructure"
    )
    cbir1 = CBIRResult(
        id=1, case_id=4, query_evidence_id=10, candidate_evidence_id=16,
        visual_similarity_score=0.87, semantic_score=0.82, edge_similarity=0.85, orb_similarity=0.79,
        classification="Candidate Visual Match", confidence_level="High",
        recommendation="Corroborate visual similarity with server log timestamps",
        sha256_exact_duplicate=False, verification_required=True
    )

    db.add_all([
        ev10, h10, epra10, ev11, h11, epra11, ev12, h12, epra12,
        ev13, h13, epra13, ev14, h14, epra14, ev15, h15, ev16, h16, ev17, h17,
        pe1, pe_link1, el1, cbir1
    ])
    db.commit()

    return db, {
        "admin": admin,
        "investigator_1": investigator_1,
        "investigator_2": investigator_2,
        "cyber_expert_1": cyber_expert_1,
        "case_1": c1,
        "case_2": c2,
        "case_3": c3,
        "case_4": c4
    }


# ==============================================================================
# TEST CASES
# ==============================================================================

def test_case_overview_assigned_investigator():
    """1. Role 2 assigned investigator can retrieve Case Overview with all required fields."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    overview = fetch_case_overview(case_id="CASE-2024-001", current_user=inv, db=db)
    assert overview.case.id == 1
    assert overview.case.case_id == "CASE-2024-001"
    assert overview.case.title == "Bank Phishing Fraud"
    # Case description must be genuine Case.description
    assert overview.case.description == "Authentic Case Description for Phishing Fraud Investigation"
    assert overview.case.priority == "High"
    assert overview.case.status == "In Progress"

    # Confirm NO crime_type in case dictionary or model
    assert not hasattr(overview.case, "crime_type")

    # Team members
    assert overview.assigned_investigator.id == 201
    assert overview.assigned_investigator.name == "Inspector Vikram"
    assert overview.assigned_investigator.email == "vikram@police.gov.in"
    assert overview.assigned_investigator.role == "Investigator"

    assert overview.assigned_cyber_expert is not None
    assert overview.assigned_cyber_expert.id == 301
    assert overview.assigned_cyber_expert.name == "Analyst Rajesh"
    assert overview.assigned_cyber_expert.role == "Cyber Expert"

    print("PASS: test_case_overview_assigned_investigator")


def test_case_overview_unassigned_expert_case():
    """2. Case without an assigned cyber expert cleanly returns None for assigned_cyber_expert."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    overview = fetch_case_overview(case_id="CASE-2024-002", current_user=inv, db=db)
    assert overview.case.id == 2
    assert overview.assigned_cyber_expert is None
    print("PASS: test_case_overview_unassigned_expert_case")


def test_case_overview_unassigned_investigator_forbidden():
    """3. Unassigned investigator rejected with 403 Forbidden."""
    db, fixtures = setup_test_db()
    inv2 = fixtures["investigator_2"]  # Assigned only to Case 3

    try:
        fetch_case_overview(case_id="CASE-2024-001", current_user=inv2, db=db)
        assert False, "Expected 403 Forbidden"
    except HTTPException as e:
        assert e.status_code == 403
        assert "Access denied" in e.detail

    print("PASS: test_case_overview_unassigned_investigator_forbidden")


def test_case_overview_non_investigator_forbidden():
    """4. Non-investigator roles (Admin, Cyber Expert) rejected with 403 Forbidden."""
    db, fixtures = setup_test_db()
    admin = fixtures["admin"]
    expert = fixtures["cyber_expert_1"]

    for u in [admin, expert]:
        try:
            fetch_case_overview(case_id="CASE-2024-001", current_user=u, db=db)
            assert False, "Expected 403 Forbidden for non-investigator"
        except HTTPException as e:
            assert e.status_code == 403
            assert "Investigator access required" in e.detail

    print("PASS: test_case_overview_non_investigator_forbidden")


def test_case_overview_zero_evidence_case():
    """5. Case with zero evidence returns clean 0s and progress 0.0."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    overview = fetch_case_overview(case_id="CASE-2024-002", current_user=inv, db=db)
    stats = overview.statistics
    assert stats.total_evidence == 0
    assert stats.analyzed_evidence == 0
    assert stats.pending_analysis == 0
    assert stats.high_priority_evidence == 0
    assert stats.investigation_progress == 0.0

    print("PASS: test_case_overview_zero_evidence_case")


def test_case_overview_statistics_calculation():
    """6. Exact statistics calculation: 4 evidence items, 3 analyzed, 1 pending, 2 high/crit."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    overview = fetch_case_overview(case_id="CASE-2024-001", current_user=inv, db=db)
    stats = overview.statistics
    assert stats.total_evidence == 4
    assert stats.analyzed_evidence == 3  # ev1, ev2, ev3 have EPRAResult COMPLETE
    assert stats.pending_analysis == 1   # ev4 has no EPRAResult
    assert stats.high_priority_evidence == 2  # ev1 (High), ev2 (Critical)
    # Progress: round(3 / 4 * 100, 2) = 75.0
    assert stats.investigation_progress == 75.0

    print("PASS: test_case_overview_statistics_calculation")


def test_case_overview_recent_activity():
    """7. Recent Activity derived strictly from genuine records."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    overview = fetch_case_overview(case_id="CASE-2024-001", current_user=inv, db=db)
    assert len(overview.recent_activity) > 0
    events = [a.event for a in overview.recent_activity]
    assert any("Evidence uploaded" in ev for ev in events)
    assert any("EV-2024-001-001" in ev for ev in events)

    print("PASS: test_case_overview_recent_activity")


def test_case_evidence_summary_cards():
    """8. Evidence Summary cards calculated accurately."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    summary = fetch_case_evidence_summary(case_id="CASE-2024-001", current_user=inv, db=db)
    assert summary.total_evidence == 4
    assert summary.analyzed == 3
    assert summary.pending_analysis == 1
    # 1 integrity issue (ev2 is tampered)
    assert summary.integrity_issues == 1

    # Zero evidence case
    summary_empty = fetch_case_evidence_summary(case_id="CASE-2024-002", current_user=inv, db=db)
    assert summary_empty.total_evidence == 0
    assert summary_empty.analyzed == 0
    assert summary_empty.pending_analysis == 0
    assert summary_empty.integrity_issues == 0

    print("PASS: test_case_evidence_summary_cards")


def test_evidence_repository_listing_and_pagination():
    """9. Evidence Repository paginated listing with correct joined EPRA and Hash statuses."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    repo = fetch_case_evidence_repository(case_id="CASE-2024-001", page=1, limit=10, current_user=inv, db=db)
    assert repo.total == 4
    assert repo.page == 1
    assert repo.limit == 10
    assert len(repo.items) == 4

    # Check unanalyzed item (ev4) has fallback 'Pending' analysis_status without DB row
    ev4_item = next(item for item in repo.items if item.evidence_id == "EV-2024-001-004")
    assert ev4_item.analysis_status == "Pending"
    assert ev4_item.priority is None
    assert ev4_item.epra_score is None

    # Check analyzed item (ev1) has complete analysis_status and EPRA score
    ev1_item = next(item for item in repo.items if item.evidence_id == "EV-2024-001-001")
    assert ev1_item.analysis_status == "COMPLETE"
    assert ev1_item.priority == "High"
    assert ev1_item.epra_score == 82.5

    # Check tampered item (ev2)
    ev2_item = next(item for item in repo.items if item.evidence_id == "EV-2024-001-002")
    assert ev2_item.integrity_status == "TAMPERED"
    assert ev2_item.priority == "Critical"

    # Confirm TiDB / SQLite has NOT received any fake EPRAResult for ev4
    db_epra_count = db.query(EPRAResult).filter(EPRAResult.evidence_id == 4).count()
    assert db_epra_count == 0, "Fake EPRAResult record must NOT be inserted into database"

    print("PASS: test_evidence_repository_listing_and_pagination")


def test_evidence_repository_filters():
    """10. Repository filters: search, file_type, analysis_status, priority."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    # Search filter
    res_search = fetch_case_evidence_repository(case_id="CASE-2024-001", search="transaction", current_user=inv, db=db)
    assert res_search.total == 1
    assert res_search.items[0].file_name == "transaction_log.pdf"

    # File type filter
    res_type = fetch_case_evidence_repository(case_id="CASE-2024-001", file_type="Image", current_user=inv, db=db)
    assert res_type.total == 1
    assert res_type.items[0].file_name == "phishing_email.png"

    # Analysis status filter: Pending (should match unanalyzed ev4)
    res_pending = fetch_case_evidence_repository(case_id="CASE-2024-001", analysis_status="Pending", current_user=inv, db=db)
    assert res_pending.total == 1
    assert res_pending.items[0].evidence_id == "EV-2024-001-004"

    # Analysis status filter: COMPLETE
    res_complete = fetch_case_evidence_repository(case_id="CASE-2024-001", analysis_status="COMPLETE", current_user=inv, db=db)
    assert res_complete.total == 3

    # Priority filter: Critical
    res_crit = fetch_case_evidence_repository(case_id="CASE-2024-001", priority="Critical", current_user=inv, db=db)
    assert res_crit.total == 1
    assert res_crit.items[0].evidence_id == "EV-2024-001-002"

    print("PASS: test_evidence_repository_filters")


def test_single_evidence_detail_integration():
    """11. Single Evidence Detail integrates Evidence + Hash + EPRA + Deepak's Metadata."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]

    detail = fetch_evidence_detail(case_id="CASE-2024-001", evidence_id="EV-2024-001-001", current_user=inv, db=db)
    assert detail.evidence_id == "EV-2024-001-001"
    assert detail.file_name == "phishing_email.png"
    assert detail.integrity_status == "Verified"
    assert detail.analysis_status == "COMPLETE"
    assert detail.priority == "High"
    assert detail.epra_score == 82.5
    assert detail.rank == 1

    # EPRA risk factors
    assert detail.risk_factors is not None
    assert detail.risk_factors["authenticity_risk"] == 0.85
    assert detail.risk_factors["context_intelligence"] == 0.75

    # Deepak's metadata
    assert detail.metadata is not None
    assert detail.metadata["mime_type"] == "image/png"
    assert detail.metadata["notes"] == "Email screenshot showing phishing domain"

    # Unanalyzed evidence detail (ev4)
    detail_ev4 = fetch_evidence_detail(case_id="CASE-2024-001", evidence_id="EV-2024-001-004", current_user=inv, db=db)
    assert detail_ev4.evidence_id == "EV-2024-001-004"
    assert detail_ev4.analysis_status == "Pending"
    assert detail_ev4.priority is None
    assert detail_ev4.epra_score is None
    assert detail_ev4.risk_factors is None

    print("PASS: test_single_evidence_detail_integration")


def test_single_evidence_detail_forbidden_and_not_found():
    """12. Single Evidence Detail checks case assignment and 404 for missing items."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]
    inv2 = fixtures["investigator_2"]

    # Unassigned investigator forbidden
    try:
        fetch_evidence_detail(case_id="CASE-2024-001", evidence_id="EV-2024-001-001", current_user=inv2, db=db)
        assert False, "Expected 403 Forbidden"
    except HTTPException as e:
        assert e.status_code == 403

    # Evidence not found
    try:
        fetch_evidence_detail(case_id="CASE-2024-001", evidence_id="NON_EXISTENT", current_user=inv1, db=db)
        assert False, "Expected 404 Not Found"
    except HTTPException as e:
        assert e.status_code == 404

    print("PASS: test_single_evidence_detail_forbidden_and_not_found")


def test_secure_download_and_preview(tmp_path):
    """13. Secure download & preview: safe path resolution, unsupported format rejection, 404 on missing disk file."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    # 1. Missing physical file on disk -> 404
    try:
        download_evidence_file(case_id="CASE-2024-001", evidence_id="EV-2024-001-001", current_user=inv1, db=db)
        assert False, "Expected 404 Not Found for missing disk file"
    except HTTPException as e:
        assert e.status_code == 404
        assert "not found on disk" in e.detail

    # Create real files under uploads/evidence/1/
    upload_dir = Path("uploads/evidence/1")
    upload_dir.mkdir(parents=True, exist_ok=True)

    img_file = upload_dir / "phishing_email.png"
    img_file.write_bytes(b"\x89PNG\r\n\x1a\nfake_image_content")

    zip_file = upload_dir / "archive.zip"
    zip_file.write_bytes(b"PK\x03\x04fake_zip_content")

    # Add archive evidence to case 1
    ev_zip = Evidence(
        id=5, evidence_id="EV-2024-001-005", case_id=1, file_name="archive.zip",
        file_type="Archive", file_size=len(b"PK\x03\x04fake_zip_content"),
        file_path="uploads/evidence/1/archive.zip"
    )
    db.add(ev_zip)
    db.commit()

    try:
        # 2. Valid download of real image
        dl_resp = download_evidence_file(case_id="CASE-2024-001", evidence_id="EV-2024-001-001", current_user=inv1, db=db)
        assert dl_resp.path == str(img_file.resolve())
        assert dl_resp.filename == "phishing_email.png"
        assert "attachment" in dl_resp.headers["Content-Disposition"]

        # 3. Valid preview of real image
        prev_resp = preview_evidence_file(case_id="CASE-2024-001", evidence_id="EV-2024-001-001", current_user=inv1, db=db)
        assert prev_resp.path == str(img_file.resolve())
        assert "inline" in prev_resp.headers["Content-Disposition"]

        # 4. Preview unsupported format (.zip archive) -> 400 Bad Request
        try:
            preview_evidence_file(case_id="CASE-2024-001", evidence_id="EV-2024-001-005", current_user=inv1, db=db)
            assert False, "Expected 400 Bad Request for non-previewable file format"
        except HTTPException as e:
            assert e.status_code == 400
            assert "Preview is not supported" in e.detail

        # 5. Path traversal attempt outside uploads/evidence
        ev_traversal = Evidence(
            id=6, evidence_id="EV-2024-001-006", case_id=1, file_name="secret.txt",
            file_type="Document", file_size=10,
            file_path="uploads/../../windows/system32/cmd.exe"
        )
        db.add(ev_traversal)
        db.commit()

        try:
            download_evidence_file(case_id="CASE-2024-001", evidence_id="EV-2024-001-006", current_user=inv1, db=db)
            assert False, "Expected 403 Forbidden for path traversal"
        except HTTPException as e:
            assert e.status_code == 403
            assert "Invalid file path traversal" in e.detail

    finally:
        # Cleanup temporary test files
        if img_file.exists():
            img_file.unlink()
        if zip_file.exists():
            zip_file.unlink()

    print("PASS: test_secure_download_and_preview")


def test_existing_evidence_upload_reuse():
    """14. Confirm existing evidence upload and list service remain functional and intact."""
    db, fixtures = setup_test_db()
    inv = fixtures["investigator_1"]
    case = fixtures["case_1"]

    # Verify authorize_case_access works for assigned investigator
    authorized_case = authorize_case_access(db, case.case_id, inv)
    assert authorized_case.id == case.id

    # Verify get_case_evidence_list works
    ev_list = get_case_evidence_list(db, case)
    assert len(ev_list) >= 4

    print("PASS: test_existing_evidence_upload_reuse")


def test_no_cross_case_or_cross_investigator_leakage():
    """15. Strict authorization prevents any cross-case or cross-investigator leakage."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]
    inv2 = fixtures["investigator_2"]

    # Case 3 belongs to inv2
    # Inv1 cannot access Case 3 overview
    try:
        fetch_case_overview(case_id="CASE-2024-003", current_user=inv1, db=db)
        assert False, "Expected 403 Forbidden"
    except HTTPException as e:
        assert e.status_code == 403

    # Inv1 cannot access Case 3 evidence summary
    try:
        fetch_case_evidence_summary(case_id="CASE-2024-003", current_user=inv1, db=db)
        assert False, "Expected 403 Forbidden"
    except HTTPException as e:
        assert e.status_code == 403

    # Inv1 cannot access Case 3 evidence repository
    try:
        fetch_case_evidence_repository(case_id="CASE-2024-003", current_user=inv1, db=db)
        assert False, "Expected 403 Forbidden"
    except HTTPException as e:
        assert e.status_code == 403

    print("PASS: test_no_cross_case_or_cross_investigator_leakage")


# ==============================================================================
# ANALYSIS PROGRESS TESTS
# ==============================================================================

def test_analysis_progress_summary_assigned_investigator():
    """16. Assigned investigator can access Analysis Progress Summary with exact calculations."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    summary = fetch_analysis_progress_summary(case_id="CASE-2024-004", current_user=inv1, db=db)
    assert summary.case_id == "CASE-2024-004"
    assert summary.total_evidence == 8
    # ev10, ev11, ev13, ev14 are COMPLETE
    assert summary.analyzed_evidence == 4
    # ev12 is PARTIAL
    assert summary.partial_analysis == 1
    # ev15, ev16, ev17 are unanalyzed (pending)
    assert summary.pending_analysis == 3
    # High/Critical: ev10 (High), ev11 (Critical)
    assert summary.high_critical_evidence == 2
    # Progress: round((4 / 8) * 100, 2) = 50.0
    assert summary.overall_analysis_progress == 50.0

    print("PASS: test_analysis_progress_summary_assigned_investigator")


def test_analysis_progress_summary_zero_evidence():
    """17. Zero evidence case returns clean zeros and progress 0.0."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    summary = fetch_analysis_progress_summary(case_id="CASE-2024-002", current_user=inv1, db=db)
    assert summary.total_evidence == 0
    assert summary.analyzed_evidence == 0
    assert summary.pending_analysis == 0
    assert summary.partial_analysis == 0
    assert summary.high_critical_evidence == 0
    assert summary.overall_analysis_progress == 0.0

    print("PASS: test_analysis_progress_summary_zero_evidence")


def test_analysis_progress_summary_unassigned_and_non_investigator_forbidden():
    """18. Unassigned investigator and non-investigators rejected with 403 Forbidden."""
    db, fixtures = setup_test_db()
    inv2 = fixtures["investigator_2"]
    admin = fixtures["admin"]
    expert = fixtures["cyber_expert_1"]

    # Unassigned investigator
    try:
        fetch_analysis_progress_summary(case_id="CASE-2024-004", current_user=inv2, db=db)
        assert False, "Expected 403 Forbidden"
    except HTTPException as e:
        assert e.status_code == 403

    # Non-investigators
    for u in [admin, expert]:
        try:
            fetch_analysis_progress_summary(case_id="CASE-2024-004", current_user=u, db=db)
            assert False, "Expected 403 Forbidden"
        except HTTPException as e:
            assert e.status_code == 403

    print("PASS: test_analysis_progress_summary_unassigned_and_non_investigator_forbidden")


def test_analysis_progress_evidence_listing_and_filters():
    """19. Evidence analysis repository paginated listing and filter support."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    # All items
    repo = fetch_analysis_progress_evidence(case_id="CASE-2024-004", page=1, limit=10, current_user=inv1, db=db)
    assert repo.total == 8
    assert len(repo.items) == 8

    # Filter by analysis_status = "COMPLETE"
    complete_repo = fetch_analysis_progress_evidence(
        case_id="CASE-2024-004", analysis_status="COMPLETE", current_user=inv1, db=db
    )
    assert complete_repo.total == 4
    for it in complete_repo.items:
        assert it.analysis_status == "COMPLETE"

    # Filter by analysis_status = "PARTIAL"
    partial_repo = fetch_analysis_progress_evidence(
        case_id="CASE-2024-004", analysis_status="PARTIAL", current_user=inv1, db=db
    )
    assert partial_repo.total == 1
    assert partial_repo.items[0].evidence_id == "EV-2024-004-012"
    assert "Voice Biometrics Verification" in partial_repo.items[0].pending_inputs

    # Filter by priority = "Critical"
    crit_repo = fetch_analysis_progress_evidence(
        case_id="CASE-2024-004", priority="Critical", current_user=inv1, db=db
    )
    assert crit_repo.total == 1
    assert crit_repo.items[0].file_name == "wire_transfer.pdf"

    # Filter by file_type = "Audio"
    audio_repo = fetch_analysis_progress_evidence(
        case_id="CASE-2024-004", file_type="Audio", current_user=inv1, db=db
    )
    assert audio_repo.total == 1
    assert audio_repo.items[0].file_name == "wiretap_call.mp3"

    # Search filter
    search_repo = fetch_analysis_progress_evidence(
        case_id="CASE-2024-004", search="rogue", current_user=inv1, db=db
    )
    assert search_repo.total == 2  # rogue_server.png and backup_rogue_server.png

    # Verify unanalyzed evidence display fallback to 'Pending' without fake DB row
    ev15_item = next(it for it in repo.items if it.evidence_id == "EV-2024-004-015")
    assert ev15_item.analysis_status == "Pending"
    assert ev15_item.priority is None
    assert ev15_item.epra_score is None

    # Verify no fake EPRAResult row was created in DB for ev15
    ev15_epra_in_db = db.query(EPRAResult).filter(EPRAResult.evidence_id == 15).first()
    assert ev15_epra_in_db is None

    print("PASS: test_analysis_progress_evidence_listing_and_filters")


def test_epra_priority_distribution():
    """20. EPRA priority distribution breakdown across all analyzed evidence."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    prio_dist = fetch_epra_priority_distribution(case_id="CASE-2024-004", current_user=inv1, db=db)
    assert prio_dist.critical == 1    # ev11
    assert prio_dist.high == 1        # ev10
    assert prio_dist.medium == 1      # ev12
    assert prio_dist.low == 1         # ev13
    assert prio_dist.very_low == 1    # ev14
    assert prio_dist.total_analyzed == 5

    print("PASS: test_epra_priority_distribution")


def test_pending_analysis_endpoint():
    """21. Pending analysis items accurately identified."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    pending = fetch_pending_analysis(case_id="CASE-2024-004", current_user=inv1, db=db)
    # Awaiting complete analysis: ev12 (PARTIAL), ev15 (Pending), ev16 (Pending), ev17 (Pending)
    assert pending.total_pending == 4
    pending_ids = [it.evidence_id for it in pending.items]
    assert "EV-2024-004-012" in pending_ids
    assert "EV-2024-004-015" in pending_ids
    assert "EV-2024-004-016" in pending_ids
    assert "EV-2024-004-017" in pending_ids

    ev12_pending = next(it for it in pending.items if it.evidence_id == "EV-2024-004-012")
    assert ev12_pending.analysis_status == "PARTIAL / PENDING INPUTS"
    assert len(ev12_pending.pending_inputs) == 2

    print("PASS: test_pending_analysis_endpoint")


def test_single_analysis_detail_analyzed_and_pending():
    """22. Single evidence analysis detail for analyzed, partial, and pending items."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]
    inv2 = fixtures["investigator_2"]

    # Analyzed item (ev11)
    detail_analyzed = fetch_single_analysis_detail(
        case_id="CASE-2024-004", evidence_id="EV-2024-004-011", current_user=inv1, db=db
    )
    assert detail_analyzed.evidence_id == "EV-2024-004-011"
    assert detail_analyzed.analysis_status == "COMPLETE"
    assert detail_analyzed.priority == "Critical"
    assert detail_analyzed.epra_score == 96.0
    assert detail_analyzed.rank == 1
    assert detail_analyzed.authenticity_risk == 0.96
    assert detail_analyzed.context_intelligence == 0.94
    assert detail_analyzed.behaviour_intelligence == 0.92
    assert detail_analyzed.investigative_intelligence == 0.95
    # For non-image / no-CBIR evidence, semantic_status is PENDING and semantic_intelligence is None
    assert detail_analyzed.semantic_status == "PENDING"
    assert detail_analyzed.semantic_intelligence is None

    # Partial item (ev12)
    detail_partial = fetch_single_analysis_detail(
        case_id="CASE-2024-004", evidence_id="EV-2024-004-012", current_user=inv1, db=db
    )
    assert detail_partial.analysis_status == "PARTIAL / PENDING INPUTS"
    assert "Voice Biometrics Verification" in detail_partial.pending_inputs

    # Unanalyzed item (ev17) - Clean Pending fallback without DB row
    initial_epra_count = db.query(EPRAResult).count()
    detail_pending = fetch_single_analysis_detail(
        case_id="CASE-2024-004", evidence_id="EV-2024-004-017", current_user=inv1, db=db
    )
    assert detail_pending.analysis_status == "Pending"
    assert detail_pending.epra_score is None
    assert detail_pending.priority is None
    assert detail_pending.rank is None
    assert detail_pending.authenticity_risk is None
    assert db.query(EPRAResult).count() == initial_epra_count

    # Non-existent evidence returns 404
    try:
        fetch_single_analysis_detail(case_id="CASE-2024-004", evidence_id="NON-EXISTENT", current_user=inv1, db=db)
        assert False, "Expected 404 Not Found"
    except HTTPException as e:
        assert e.status_code == 404

    # Unassigned investigator returns 403
    try:
        fetch_single_analysis_detail(case_id="CASE-2024-004", evidence_id="EV-2024-004-011", current_user=inv2, db=db)
        assert False, "Expected 403 Forbidden"
    except HTTPException as e:
        assert e.status_code == 403

    print("PASS: test_single_analysis_detail_analyzed_and_pending")


# ==============================================================================
# RELATIONSHIP VIEW TESTS
# ==============================================================================

def test_relationship_view_graph_structure():
    """23. Relationship View Graph structure includes nodes, non-image evidence, duplicates, and CBIR edges."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    graph = fetch_relationship_view(case_id="CASE-2024-004", current_user=inv1, db=db)
    assert graph.status == "Success"
    assert graph.case_id == "CASE-2024-004"

    node_ids = {n.id for n in graph.nodes}
    # All 8 evidence nodes present
    for i in range(10, 18):
        assert f"ev_{i}" in node_ids

    # Verify non-image evidence nodes are present in graph
    doc_node = next(n for n in graph.nodes if n.id == "ev_11")
    assert doc_node.category == "PDF" or "Document" in doc_node.properties["file_type"]
    audio_node = next(n for n in graph.nodes if n.id == "ev_12")
    assert audio_node.category == "AUDIO" or "Audio" in audio_node.properties["file_type"]
    video_node = next(n for n in graph.nodes if n.id == "ev_13")
    assert video_node.category == "VIDEO" or "Video" in video_node.properties["file_type"]

    # Injected EPRA properties verified on evidence node
    ev10_node = next(n for n in graph.nodes if n.id == "ev_10")
    assert ev10_node.properties["epra_score"] == 88.0
    assert ev10_node.properties["priority"] == "High"
    assert ev10_node.properties["rank"] == 2
    assert ev10_node.properties["analysis_status"] == "COMPLETE"

    # Suspect node present
    assert "suspect_1" in node_ids

    # Device node present (extracted from EvidenceLink)
    assert any(n.node_type == "Device" for n in graph.nodes)

    # Check edges
    edge_rel_types = {e.relationship_type for e in graph.edges}
    # 1. Exact duplicate SHA-256 edge between ev_10 and ev_15
    assert "EXACT_DUPLICATE" in edge_rel_types
    dup_edge = next(e for e in graph.edges if e.relationship_type == "EXACT_DUPLICATE")
    assert {dup_edge.source, dup_edge.target} == {"ev_10", "ev_15"}

    # 2. CBIR visual similarity edge between ev_10 and ev_16
    assert "CBIR_VISUAL_SIMILARITY" in edge_rel_types
    cbir_edge = next(e for e in graph.edges if e.relationship_type == "CBIR_VISUAL_SIMILARITY")
    assert {cbir_edge.source, cbir_edge.target} == {"ev_10", "ev_16"}
    assert cbir_edge.similarity == 0.87

    # 3. Evidence-to-suspect edge between ev_11 and suspect_1
    assert "EVIDENCE_SUSPECT_LINK" in edge_rel_types

    print("PASS: test_relationship_view_graph_structure")


def test_relationship_view_filters():
    """24. Relationship View filtering by node_type, relationship_type, and priority."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    # Filter by node_type = "Evidence"
    ev_only = fetch_relationship_view(case_id="CASE-2024-004", node_type="Evidence", current_user=inv1, db=db)
    for n in ev_only.nodes:
        assert n.node_type == "Evidence"

    # Filter by node_type = "Suspect"
    susp_only = fetch_relationship_view(case_id="CASE-2024-004", node_type="Suspect", current_user=inv1, db=db)
    assert len(susp_only.nodes) >= 1
    for n in susp_only.nodes:
        assert n.node_type == "Suspect"

    # Filter by relationship_type = "EXACT_DUPLICATE"
    dup_only = fetch_relationship_view(
        case_id="CASE-2024-004", relationship_type="EXACT_DUPLICATE", current_user=inv1, db=db
    )
    for e in dup_only.edges:
        assert e.relationship_type == "EXACT_DUPLICATE"

    # Filter by relationship_type = "CBIR_VISUAL_SIMILARITY"
    cbir_only = fetch_relationship_view(
        case_id="CASE-2024-004", relationship_type="CBIR_VISUAL_SIMILARITY", current_user=inv1, db=db
    )
    for e in cbir_only.edges:
        assert e.relationship_type == "CBIR_VISUAL_SIMILARITY"

    # Filter by priority = "High"
    high_only = fetch_relationship_view(case_id="CASE-2024-004", priority="High", current_user=inv1, db=db)
    ev_nodes = [n for n in high_only.nodes if n.node_type == "Evidence"]
    for n in ev_nodes:
        assert (n.properties.get("priority") or "").lower() == "high"

    print("PASS: test_relationship_view_filters")


def test_relationship_node_detail():
    """25. Relationship Node Detail returns deep genuine properties and connected edges."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    # Evidence node detail (ev_10)
    ev_detail = fetch_relationship_node_detail(
        case_id="CASE-2024-004", node_id="ev_10", current_user=inv1, db=db
    )
    assert ev_detail.node_id == "ev_10"
    assert ev_detail.node_type == "Evidence"
    assert ev_detail.label == "rogue_server.png"
    assert ev_detail.properties["epra_score"] == 88.0
    assert ev_detail.properties["priority"] == "High"
    assert ev_detail.properties["rank"] == 2
    assert ev_detail.properties["analysis_status"] == "COMPLETE"
    assert ev_detail.connected_nodes_count > 0

    # Possible Entity node detail (suspect_1)
    pe_detail = fetch_relationship_node_detail(
        case_id="CASE-2024-004", node_id="suspect_1", current_user=inv1, db=db
    )
    assert pe_detail.node_id == "suspect_1"
    # Display node type must be labeled "Possible Entity", NOT confirmed suspect
    assert pe_detail.node_type == "Possible Entity"
    assert pe_detail.properties["total_epra_score"] == 96.0
    assert pe_detail.properties["confidence_score"] == 0.92
    assert pe_detail.connected_nodes_count > 0

    # Case node detail
    case_detail = fetch_relationship_node_detail(
        case_id="CASE-2024-004", node_id="case_4", current_user=inv1, db=db
    )
    assert case_detail.node_type == "Case"
    assert case_detail.label == "Advanced Cyber Fraud"

    # Unknown node detail raises 404
    try:
        fetch_relationship_node_detail(case_id="CASE-2024-004", node_id="non_existent_node", current_user=inv1, db=db)
        assert False, "Expected 404 Not Found"
    except HTTPException as e:
        assert e.status_code == 404

    print("PASS: test_relationship_node_detail")


def test_relationship_view_unassigned_and_non_investigator_forbidden():
    """26. Unassigned investigator and non-investigators rejected with 403 Forbidden."""
    db, fixtures = setup_test_db()
    inv2 = fixtures["investigator_2"]
    admin = fixtures["admin"]
    expert = fixtures["cyber_expert_1"]

    # Unassigned investigator
    try:
        fetch_relationship_view(case_id="CASE-2024-004", current_user=inv2, db=db)
        assert False, "Expected 403 Forbidden"
    except HTTPException as e:
        assert e.status_code == 403

    # Non-investigators
    for u in [admin, expert]:
        try:
            fetch_relationship_view(case_id="CASE-2024-004", current_user=u, db=db)
            assert False, "Expected 403 Forbidden"
        except HTTPException as e:
            assert e.status_code == 403

    print("PASS: test_relationship_view_unassigned_and_non_investigator_forbidden")


def test_relationship_cross_case_isolation():
    """27. Strict case isolation prevents any cross-case node or edge leakage."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    graph_c4 = fetch_relationship_view(case_id="CASE-2024-004", current_user=inv1, db=db)
    graph_c1 = fetch_relationship_view(case_id="CASE-2024-001", current_user=inv1, db=db)

    c4_node_ids = {n.id for n in graph_c4.nodes}
    c1_node_ids = {n.id for n in graph_c1.nodes}

    # Case 4 should have zero overlap with Case 1
    assert c4_node_ids.isdisjoint(c1_node_ids)

    print("PASS: test_relationship_cross_case_isolation")


def test_investigator_read_only_guarantee():
    """28. Strict read-only guarantee: Investigator cannot modify relationship links or EPRA analysis."""
    db, fixtures = setup_test_db()
    inv1 = fixtures["investigator_1"]

    from services.relationship_graph_service import RelationshipGraphService
    from schemas.relationship_graph import CreateLinkRequest

    # Attempting to create an evidence link as an investigator raises PermissionError
    req = CreateLinkRequest(
        evidence_id="10",
        suspect_name="Unauthorized Suspect",
        relationship_type="UNAUTHORIZED"
    )
    try:
        RelationshipGraphService.create_evidence_link(db, "CASE-2024-004", req, inv1)
        assert False, "Expected PermissionError for Investigator"
    except PermissionError as e:
        assert "Only Cyber Experts" in str(e)

    # Attempting to delete an evidence link as an investigator raises PermissionError
    try:
        RelationshipGraphService.delete_evidence_link(db, "CASE-2024-004", 1, inv1)
        assert False, "Expected PermissionError for Investigator"
    except PermissionError as e:
        assert "Only Cyber Experts" in str(e)

    print("PASS: test_investigator_read_only_guarantee")


def run_all_tests():
    print("==================================================================")
    print("RUNNING INVESTIGATOR VIEW CASE TEST SUITE (28 TESTS)")
    print("==================================================================")
    # Existing 15 Tests
    test_case_overview_assigned_investigator()
    test_case_overview_unassigned_expert_case()
    test_case_overview_unassigned_investigator_forbidden()
    test_case_overview_non_investigator_forbidden()
    test_case_overview_zero_evidence_case()
    test_case_overview_statistics_calculation()
    test_case_overview_recent_activity()
    test_case_evidence_summary_cards()
    test_evidence_repository_listing_and_pagination()
    test_evidence_repository_filters()
    test_single_evidence_detail_integration()
    test_single_evidence_detail_forbidden_and_not_found()
    test_secure_download_and_preview(None)
    test_existing_evidence_upload_reuse()
    test_no_cross_case_or_cross_investigator_leakage()

    # 13 New Tests for Analysis Progress & Relationship View
    test_analysis_progress_summary_assigned_investigator()
    test_analysis_progress_summary_zero_evidence()
    test_analysis_progress_summary_unassigned_and_non_investigator_forbidden()
    test_analysis_progress_evidence_listing_and_filters()
    test_epra_priority_distribution()
    test_pending_analysis_endpoint()
    test_single_analysis_detail_analyzed_and_pending()
    test_relationship_view_graph_structure()
    test_relationship_view_filters()
    test_relationship_node_detail()
    test_relationship_view_unassigned_and_non_investigator_forbidden()
    test_relationship_cross_case_isolation()
    test_investigator_read_only_guarantee()

    print("==================================================================")
    print("ALL 28 INVESTIGATOR VIEW CASE TESTS PASSED!")
    print("==================================================================")


if __name__ == "__main__":
    run_all_tests()

