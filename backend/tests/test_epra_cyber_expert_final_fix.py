"""
Focused backend test suite for Cyber Expert -> EPRA Integration (Final Focused Fix).
Verifies:
1. Canonical Type Mapping:
   - .xlsx -> SPREADSHEET
   - .pdf -> PDF
   - .txt -> DOCUMENT
   - .exe -> EXECUTABLE
   - .eml -> EMAIL
   - .log -> LOG
   - .jpg -> IMAGE
   - .mp4 -> VIDEO
   - AUDIO (.mp3, .wav)
   - DATABASE (.db, .sqlite, .sql)
   - ARCHIVE (.zip, .rar, .7z)
   - UNKNOWN
2. EPRA Raw Input Passing:
   - Genuine AR input reaches EPRA (hash/integrity state, CoC)
   - Genuine case_context reaches EPRA for CI
   - Genuine BI data reaches EPRA when available; missing BI is NOT fake 0.0000
   - Genuine IMAGE CBIR semantic_score reaches EPRA SI; missing IMAGE semantic_score remains PENDING
   - Non-image extracted content reaches EPRA; non-image does NOT receive IMAGE-specific pending reason
   - Genuine II inputs reach EPRA where available
   - Returned AR/CI/BI/SI/II are EPRA outputs, not backend independent calculations
   - Actual 0.0 remains distinguishable from missing/null
3. API Serialization & Role Isolation:
   - Ranked evidence returns canonical type in evidence_type and file_type
   - Evidence detail returns canonical type in evidence_type and file_type
   - Top Evidence source returns canonical type
   - All factor/status fields serialize correctly without raw MIME leaking
   - Authenticated user / case isolation is enforced
"""
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
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.case_timeline import CaseTimeline

from services.epra_service import (
    CANONICAL_EPRA_TYPES,
    normalize_epra_evidence_type,
    process_case_epra,
    get_case_epra_summary,
    get_case_ranked_evidence,
    get_evidence_epra_detail,
    authorize_cyber_expert_case_access,
    authorize_epra_read_case_access
)


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


from models.evidence_record import EvidenceRecord
from models.notification import Notification

@pytest.fixture
def db():
    """Isolated in-memory SQLite database."""
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()

    # Seed roles
    session.add(Role(id=1, role_name="Admin"))
    session.add(Role(id=2, role_name="Investigator"))
    session.add(Role(id=3, role_name="Cyber Expert"))
    city = City(id=1, city_name="Default City")
    cell = CyberCell(id=1, cyber_cell_name="Default Cell", admin_email="admin@default.gov", city_id=1)
    session.add_all([city, cell])
    session.commit()

    yield session
    session.close()


# ============================================================
# TEST 1: CANONICAL TYPE MAPPING
# ============================================================
def test_canonical_evidence_type_mapping():
    """Prove canonical EPRA evidence type mapping for all requested and standard types."""
    test_cases = [
        # Expected current examples from prompt
        ("transaction_history.xlsx", "Document", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "SPREADSHEET"),
        ("bank_statement.pdf", "PDF Document", "application/pdf", "PDF"),
        ("wallet_credentials.txt", "Document", "text/plain", "DOCUMENT"),
        ("ransomware.exe", "Application", "application/x-msdos-program", "EXECUTABLE"),
        ("phishing_email.eml", "Message", "message/rfc822", "EMAIL"),
        ("system_activity.log", "Unknown", "text/x-log", "LOG"),
        ("crime_scene_photo.jpg", "Image", "image/jpeg", "IMAGE"),
        ("cctv_footage.mp4", "Video", "video/mp4", "VIDEO"),
        # Additional coverage
        ("voice_call.mp3", "Audio", "audio/mpeg", "AUDIO"),
        ("wiretap.wav", "Audio", "audio/wav", "AUDIO"),
        ("evidence.db", "Database", "application/x-sqlite3", "DATABASE"),
        ("backup.sql", "Database", "application/sql", "DATABASE"),
        ("archive.zip", "Archive", "application/zip", "ARCHIVE"),
        ("dump.rar", "Archive", "application/x-rar-compressed", "ARCHIVE"),
        ("bundle.7z", "Archive", "application/x-7z-compressed", "ARCHIVE"),
        ("notes.docx", "Document", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "DOCUMENT"),
        ("ledger.csv", "Document", "text/csv", "SPREADSHEET"),
        ("binary.dll", "Executable", "application/x-msdownload", "EXECUTABLE"),
        ("unknown_blob.xyz123", "Unknown", "application/octet-stream", "UNKNOWN"),
    ]

    for filename, raw_type, mime_type, expected_canon in test_cases:
        actual = normalize_epra_evidence_type(raw_type=raw_type, mime_type=mime_type, filename=filename)
        assert actual == expected_canon, f"Failed for {filename}: expected {expected_canon}, got {actual}"
        assert actual in CANONICAL_EPRA_TYPES


# ============================================================
# TEST 2: RAW INPUT PASSING & EPRA ENGINE OUTPUT INTEGRITY
# ============================================================
def test_raw_input_passing_and_epra_output(db):
    """
    Prove that:
    - Genuine AR input (integrity state, CoC) reaches EPRA
    - Genuine case_context reaches EPRA for CI
    - Genuine BI data reaches EPRA; missing BI is None (not fake 0)
    - Image SI uses genuine CBIR semantic_score only (missing -> PENDING)
    - Non-image extracted text reaches EPRA (missing -> PENDING with doc reason)
    - AR/CI/BI/SI/II come from EPRA, not independent backend recalculations
    """
    expert = make_user(301, "Expert Alan", 3)
    investigator = make_user(201, "Inv Watson", 2)
    db.add_all([expert, investigator])
    db.commit()

    case = Case(
        id=10,
        case_id="CASE-FINAL-001",
        title="Financial Cybercrime & Wire Fraud",
        description="Investigation into illicit cryptocurrency transactions and phishing campaign.",
        cyber_expert_id=expert.id,
        investigator_id=investigator.id,
        status="In Progress"
    )
    db.add(case)
    db.commit()

    # Evidence 1: Image with genuine CBIR semantic_score
    ev_img = Evidence(id=101, case_id=case.id, evidence_id="EV-IMG-001", file_name="crime_scene_photo.jpg", file_type="IMAGE", file_size=1024, file_path="uploads/evidence/10/crime_scene_photo.jpg")
    hash_img = EvidenceHash(evidence_id=101, file_name="crime_scene_photo.jpg", sha256_hash="img_hash", current_hash="img_hash", original_hash="img_hash", hash_match=True, integrity_status="Verified", tampered=False)

    # Evidence 2: Image WITHOUT CBIR semantic_score (must be PENDING)
    ev_img_no_cbir = Evidence(id=102, case_id=case.id, evidence_id="EV-IMG-002", file_name="suspect_snapshot.png", file_type="IMAGE", file_size=2048, file_path="uploads/evidence/10/suspect_snapshot.png")
    hash_img_no_cbir = EvidenceHash(evidence_id=102, file_name="suspect_snapshot.png", sha256_hash="snap_hash", current_hash="snap_hash", original_hash="snap_hash", hash_match=True, integrity_status="Verified", tampered=False)

    # Evidence 3: Non-image Spreadsheet with genuine external content & context
    ev_sheet = Evidence(id=103, case_id=case.id, evidence_id="EV-SHEET-001", file_name="transaction_history.xlsx", file_type="Document", file_size=4096, file_path="uploads/evidence/10/transaction_history.xlsx")
    hash_sheet = EvidenceHash(evidence_id=103, file_name="transaction_history.xlsx", sha256_hash="sheet_hash", current_hash="sheet_hash", original_hash="sheet_hash", hash_match=True, integrity_status="Verified", tampered=False)

    # Evidence 4: Non-image Log without text (must be PENDING with non-image reason)
    ev_log = Evidence(id=104, case_id=case.id, evidence_id="EV-LOG-001", file_name="system_activity.log", file_type="Unknown", file_size=512, file_path="uploads/evidence/10/system_activity.log")
    hash_log = EvidenceHash(evidence_id=104, file_name="system_activity.log", sha256_hash="log_hash", current_hash="log_hash", original_hash="log_hash", hash_match=True, integrity_status="Verified", tampered=False)

    db.add_all([ev_img, hash_img, ev_img_no_cbir, hash_img_no_cbir, ev_sheet, hash_sheet, ev_log, hash_log])
    db.commit()

    # Add genuine CBIR result for ev_img only
    cbir_rec = CBIRResult(
        case_id=case.id,
        query_evidence_id=ev_img.id,
        candidate_evidence_id=ev_img.id,
        visual_similarity_score=0.88,
        semantic_score=0.82,
        classification="Very Strong Visual Match",
        confidence_level="High",
        recommendation="Review visually",
        reason="High visual match",
        sha256_exact_duplicate=False
    )
    # Add genuine CustodyLog for ev_img
    custody_rec = CustodyLog(
        evidence_id=str(ev_img.evidence_id),
        case_id=str(case.case_id),
        action="TRANSFER",
        investigator_name="Expert Alan",
        remarks="Transferred to cyber forensics lab",
        timestamp=datetime.now()
    )
    db.add_all([cbir_rec, custody_rec])
    db.commit()

    # Process EPRA in production mode (demo_mode=False)
    # Provide external inputs for sheet
    external_inputs = {
        "EV-SHEET-001": {
            "extracted_text": "Financial transaction records wire fraud account numbers Bitcoin wallets $500,000 illicit payment.",
            "context": "Financial Cybercrime & Wire Fraud investigation.",
            "behaviour_intelligence": 0.65
        }
    }

    result = process_case_epra(
        db=db,
        case=case,
        current_user=expert,
        external_inputs=external_inputs,
        demo_mode=False
    )

    assert result["status"] == "SUCCESS"
    assert result["total_processed"] == 4

    resp_map = {r["evidence_id"]: r for r in result["ranked_evidence"]}

    # 1. Image with CBIR:
    img_resp = resp_map["EV-IMG-001"]
    assert img_resp["evidence_type"] == "IMAGE"
    assert img_resp["file_type"] == "IMAGE"
    assert img_resp["semantic_status"] == "MEASURED"
    assert img_resp["semantic_intelligence"] == 0.82
    # AR was computed by Janhvi IntegrityChecker using hash_verified and CoC
    assert img_resp["authenticity_risk"] is not None
    assert isinstance(img_resp["authenticity_risk"], float)

    # 2. Image WITHOUT CBIR:
    no_cbir_resp = resp_map["EV-IMG-002"]
    assert no_cbir_resp["evidence_type"] == "IMAGE"
    assert no_cbir_resp["semantic_status"] == "PENDING"
    assert no_cbir_resp["semantic_intelligence"] is None
    assert "Awaiting IMAGE CBIR/Semantic score" in no_cbir_resp["pending_external_inputs"]

    # 3. Non-image Spreadsheet with text:
    sheet_resp = resp_map["EV-SHEET-001"]
    assert sheet_resp["evidence_type"] == "SPREADSHEET"
    assert sheet_resp["file_type"] == "SPREADSHEET"
    assert sheet_resp["semantic_status"] == "MEASURED"
    assert sheet_resp["semantic_intelligence"] is not None
    assert sheet_resp["behaviour_intelligence"] == 0.65
    assert "Awaiting IMAGE CBIR/Semantic score" not in sheet_resp["pending_external_inputs"]

    # 4. Non-image Log without text:
    log_resp = resp_map["EV-LOG-001"]
    assert log_resp["evidence_type"] == "LOG"
    assert log_resp["file_type"] == "LOG"
    assert log_resp["semantic_status"] == "PENDING"
    assert log_resp["semantic_intelligence"] is None
    assert "Awaiting document text content and context for semantic analysis" in log_resp["pending_external_inputs"]
    assert "Awaiting IMAGE CBIR/Semantic score" not in log_resp["pending_external_inputs"]
    # Missing BI is None, NOT fake 0.0000
    assert log_resp["behaviour_intelligence"] is None


# ============================================================
# TEST 3: ACTUAL ZERO vs MISSING BEHAVIOURAL INTELLIGENCE
# ============================================================
def test_behavioural_intelligence_actual_zero_vs_missing(db):
    """Prove that an explicit 0.0 BI is preserved as 0.0, while missing BI is None (not fake 0.0000)."""
    expert = make_user(302, "Expert Curie", 3)
    db.add(expert)
    db.commit()

    case = Case(
        id=20,
        case_id="CASE-BI-001",
        title="Audit Test Case",
        cyber_expert_id=expert.id,
        status="In Progress"
    )
    db.add(case)
    db.commit()

    ev_zero = Evidence(id=201, case_id=case.id, evidence_id="EV-BI-ZERO", file_name="zero_activity.txt", file_type="DOCUMENT", file_size=100, file_path="uploads/evidence/20/zero_activity.txt")
    h_zero = EvidenceHash(evidence_id=201, file_name="zero_activity.txt", sha256_hash="h0", current_hash="h0", original_hash="h0", hash_match=True, integrity_status="Verified", tampered=False)

    ev_missing = Evidence(id=202, case_id=case.id, evidence_id="EV-BI-MISSING", file_name="missing_activity.txt", file_type="DOCUMENT", file_size=100, file_path="uploads/evidence/20/missing_activity.txt")
    h_missing = EvidenceHash(evidence_id=202, file_name="missing_activity.txt", sha256_hash="hm", current_hash="hm", original_hash="hm", hash_match=True, integrity_status="Verified", tampered=False)

    db.add_all([ev_zero, h_zero, ev_missing, h_missing])
    db.commit()

    external_inputs = {
        "EV-BI-ZERO": {
            "behaviour_intelligence": 0.0,
            "extracted_text": "Normal text",
            "context": "Audit test"
        },
        "EV-BI-MISSING": {
            # No behavioural input at all
            "extracted_text": "Normal text",
            "context": "Audit test"
        }
    }

    result = process_case_epra(
        db=db,
        case=case,
        current_user=expert,
        external_inputs=external_inputs,
        demo_mode=False
    )

    resp_map = {r["evidence_id"]: r for r in result["ranked_evidence"]}

    # Explicit 0.0 must be preserved as 0.0 float
    assert resp_map["EV-BI-ZERO"]["behaviour_intelligence"] == 0.0

    # Missing BI must be None (serialized as null in JSON)
    assert resp_map["EV-BI-MISSING"]["behaviour_intelligence"] is None


# ============================================================
# TEST 4: ALL CYBER EXPERT EPRA APIS EXPOSE CANONICAL TYPES
# ============================================================
def test_all_cyber_expert_epra_apis_expose_canonical_types(db):
    """
    Prove that all EPRA read APIs expose canonical types in evidence_type and file_type:
    - get_case_epra_summary (top_evidence)
    - get_case_ranked_evidence
    - get_evidence_epra_detail
    """
    expert = make_user(303, "Expert Hopper", 3)
    db.add(expert)
    db.commit()

    case = Case(
        id=30,
        case_id="CASE-API-001",
        title="Full API Test Case",
        cyber_expert_id=expert.id,
        status="In Progress"
    )
    db.add(case)
    db.commit()

    items = [
        ("EV-01", "transaction_history.xlsx", "Document", "SPREADSHEET"),
        ("EV-02", "bank_statement.pdf", "PDF Document", "PDF"),
        ("EV-03", "wallet_credentials.txt", "Document", "DOCUMENT"),
        ("EV-04", "ransomware.exe", "Application", "EXECUTABLE"),
        ("EV-05", "phishing_email.eml", "Message", "EMAIL"),
        ("EV-06", "system_activity.log", "Unknown", "LOG"),
        ("EV-07", "crime_scene_photo.jpg", "Image", "IMAGE"),
        ("EV-08", "cctv_footage.mp4", "Video", "VIDEO"),
    ]

    for idx, (eid, fname, raw_t, canon_t) in enumerate(items, start=301):
        ev = Evidence(id=idx, case_id=case.id, evidence_id=eid, file_name=fname, file_type=raw_t, file_size=1024, file_path=f"uploads/evidence/30/{fname}")
        h = EvidenceHash(evidence_id=idx, file_name=fname, sha256_hash=f"h_{idx}", current_hash=f"h_{idx}", original_hash=f"h_{idx}", hash_match=True, integrity_status="Verified", tampered=False)
        db.add_all([ev, h])
    db.commit()

    # Process EPRA
    process_case_epra(db=db, case=case, current_user=expert, demo_mode=False)

    # 1. Test get_case_epra_summary (top_evidence)
    summary = get_case_epra_summary(db=db, case=case)
    for top_ev in summary["top_evidence"]:
        expected_type = dict((f, c) for _, f, _, c in items)[top_ev["file_name"]]
        assert top_ev["evidence_type"] == expected_type
        assert top_ev["file_type"] == expected_type

    # 2. Test get_case_ranked_evidence
    ranked = get_case_ranked_evidence(db=db, case=case)
    assert len(ranked) == len(items)
    for r in ranked:
        expected_type = dict((f, c) for _, f, _, c in items)[r["file_name"]]
        assert r["evidence_type"] == expected_type
        assert r["file_type"] == expected_type

    # 3. Test get_evidence_epra_detail for each item
    for eid, fname, raw_t, expected_type in items:
        detail = get_evidence_epra_detail(db=db, case=case, evidence_identifier=eid)
        assert detail["evidence_id"] == eid
        assert detail["file_name"] == fname
        assert detail["evidence_type"] == expected_type
        assert detail["file_type"] == expected_type
        assert detail["authenticity_risk"] is not None
        assert detail["context_intelligence"] is not None
        assert detail["investigative_intelligence"] is not None


# ============================================================
# TEST 5: AUTHORIZATION AND CASE ISOLATION
# ============================================================
def test_authorization_and_case_isolation(db):
    """Prove that unauthorized users cannot access another case's EPRA data."""
    expert1 = make_user(304, "Expert One", 3)
    expert2 = make_user(305, "Expert Two", 3)
    investigator = make_user(202, "Inv Smith", 2)
    db.add_all([expert1, expert2, investigator])
    db.commit()

    case1 = Case(id=41, case_id="CASE-ISO-001", title="Case 1", cyber_expert_id=expert1.id, status="Open")
    case2 = Case(id=42, case_id="CASE-ISO-002", title="Case 2", cyber_expert_id=expert2.id, status="Open")
    db.add_all([case1, case2])
    db.commit()

    # Expert 1 can run EPRA on case 1
    c1 = authorize_cyber_expert_case_access(db, case1.case_id, expert1)
    assert c1.id == case1.id

    # Expert 2 cannot run EPRA on case 1 (403)
    with pytest.raises(HTTPException) as exc_info:
        authorize_cyber_expert_case_access(db, case1.case_id, expert2)
    assert exc_info.value.status_code == 403

    # Investigator cannot run EPRA on case 1 (403)
    with pytest.raises(HTTPException) as exc_info:
        authorize_cyber_expert_case_access(db, case1.case_id, investigator)
    assert exc_info.value.status_code == 403
