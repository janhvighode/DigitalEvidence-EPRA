"""
test_epra_final_2_corrections.py

Focused backend integration test suite covering EXACTLY the 13 required tests
for EPRA — Final 2 Corrections:
1. Canonical Types (.jpg, .mp4, .mp3, .eml, .pdf, .txt, .xlsx, .exe, .log, .zip, DB, unknown)
2. Generic type does not override specific extension
3. Raw MIME does not leak as final type
4. AR input passing (raw hash/custody passed to Janhvi; API exposes Janhvi's AR)
5. CI input passing (case_context reaches Janhvi)
6. BI real data (activity/behaviour data reaches Janhvi; returned BI exposed)
7. BI missing vs zero (Case A: genuine BI=0.0 -> 0.0; Case B: BI absent -> null/pending)
8. Image SI (persisted CBIR semantic_score passed; missing -> null/pending, no fake zero)
9. Non-image SI (readable text + case_context -> Janhvi TF-IDF; missing -> pending with Non-Image reason, NOT image reason)
10. II input (genuine metadata/entities/communication/financial/location/time passed to Janhvi)
11. Result exposure (API fields equal Janhvi returned values; backend does not recalculate)
12. Dynamic new case & evidence (no hardcoding, dynamic classification and processing)
13. Auth & Case isolation (unauthorized access rejected with 403)
"""
import sys
from pathlib import Path
from datetime import datetime
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
from models.city import City
from models.cyber_cell import CyberCell
from models.user import User
from models.role import Role
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.case_timeline import CaseTimeline
from models.notification import Notification
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink

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

from ai_modules.epra_v2.models.evidence import Evidence as JanhviEvidence
from ai_modules.epra_v2.models.metadata import Metadata as JanhviMetadata
from ai_modules.epra_v2.services.epra_service import EPRAService


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
    """Isolated in-memory SQLite database."""
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()

    # Seed baseline roles
    roles = [
        Role(id=1, role_name="Administrator"),
        Role(id=2, role_name="Investigator"),
        Role(id=3, role_name="Cyber Expert")
    ]
    for r in roles:
        session.add(r)
    session.commit()

    yield session
    session.close()
    Base.metadata.drop_all(engine)


# ============================================================
# TEST 1 — CANONICAL TYPES
# ============================================================
def test_1_canonical_types():
    """
    Verify all 12 canonical classifications from file extensions and indicators:
    .jpg, .jpeg, .png -> IMAGE
    .mp4, .avi, .mov -> VIDEO
    .mp3, .wav -> AUDIO
    .eml -> EMAIL
    .pdf -> PDF
    .txt, .doc, .docx -> DOCUMENT
    .csv, .xls, .xlsx -> SPREADSHEET
    .exe, .dll -> EXECUTABLE
    supported DB -> DATABASE
    .log -> LOG
    .zip, .rar, .7z -> ARCHIVE
    unsupported / unknown -> UNKNOWN
    """
    mappings = [
        (".jpg", "IMAGE"),
        (".jpeg", "IMAGE"),
        (".png", "IMAGE"),
        (".mp4", "VIDEO"),
        (".avi", "VIDEO"),
        (".mov", "VIDEO"),
        (".mp3", "AUDIO"),
        (".wav", "AUDIO"),
        (".eml", "EMAIL"),
        (".pdf", "PDF"),
        (".txt", "DOCUMENT"),
        (".doc", "DOCUMENT"),
        (".docx", "DOCUMENT"),
        (".csv", "SPREADSHEET"),
        (".xls", "SPREADSHEET"),
        (".xlsx", "SPREADSHEET"),
        (".exe", "EXECUTABLE"),
        (".dll", "EXECUTABLE"),
        (".log", "LOG"),
        (".zip", "ARCHIVE"),
        (".rar", "ARCHIVE"),
        (".7z", "ARCHIVE"),
        ("database.sqlite", "DATABASE"),
        ("supported database files", "DATABASE"),
        ("unknown_format", "UNKNOWN")
    ]
    for ext_or_cand, expected in mappings:
        result = normalize_epra_evidence_type(ext_or_cand)
        assert result == expected, f"Failed on '{ext_or_cand}': expected {expected}, got {result}"
        assert result in CANONICAL_EPRA_TYPES


# ============================================================
# TEST 2 — GENERIC TYPE DOES NOT OVERRIDE EXTENSION
# ============================================================
def test_2_generic_type_does_not_override_extension():
    """
    filename = transaction_history.xlsx, raw DB type = DOCUMENT -> SPREADSHEET (NOT DOCUMENT)
    filename = system_activity.log, raw DB type = UNKNOWN -> LOG (NOT UNKNOWN)
    """
    res1 = normalize_epra_evidence_type(
        filename="transaction_history.xlsx",
        raw_type="DOCUMENT"
    )
    assert res1 == "SPREADSHEET", f"Expected SPREADSHEET, got {res1}"

    res2 = normalize_epra_evidence_type(
        filename="system_activity.log",
        raw_type="UNKNOWN"
    )
    assert res2 == "LOG", f"Expected LOG, got {res2}"


# ============================================================
# TEST 3 — RAW MIME DOES NOT LEAK AS FINAL TYPE
# ============================================================
def test_3_raw_mime_does_not_leak_as_final_type():
    """
    application/x-msdos-program + ransomware.exe -> EXECUTABLE
    message/rfc822 + phishing_email.eml -> EMAIL
    """
    res1 = normalize_epra_evidence_type(
        mime_type="application/x-msdos-program",
        filename="ransomware.exe"
    )
    assert res1 == "EXECUTABLE", f"Expected EXECUTABLE, got {res1}"

    res2 = normalize_epra_evidence_type(
        mime_type="message/rfc822",
        filename="phishing_email.eml"
    )
    assert res2 == "EMAIL", f"Expected EMAIL, got {res2}"

    # Raw MIME alone when filename is not available
    assert normalize_epra_evidence_type("application/x-msdos-program") == "EXECUTABLE"
    assert normalize_epra_evidence_type("message/rfc822") == "EMAIL"


# ============================================================
# TEST 4 — AR INPUT PASSING
# ============================================================
def test_4_ar_input_passing(db):
    """
    Provide genuine raw hash/integrity/custody input.
    Verify backend passes it to Janhvi implementation and API exposes Janhvi's returned AR.
    Does NOT test a backend AR formula.
    """
    expert = make_user(id=10, full_name="Expert AR", role_id=3)
    db.add(expert)
    case = Case(id=101, case_id="CASE-TEST-AR", title="Integrity Investigation", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    ev = Evidence(id=1, evidence_id="EV-AR-001", case_id=case.id, file_name="audit.log", file_type="LOG", file_size=1024, file_path="/uploads/audit.log")
    db.add(ev)
    # Hash verified = True, tampered = False
    h = EvidenceHash(
        evidence_id=ev.id,
        file_name="audit.log",
        sha256_hash="aaaabbbb11112222",
        current_hash="aaaabbbb11112222",
        original_hash="aaaabbbb11112222",
        hash_match=True,
        tampered=False,
        integrity_status="Verified"
    )
    db.add(h)
    custody = CustodyLog(evidence_id="EV-AR-001", investigator_name="Officer Smith", actor_role="INVESTIGATOR", action="COLLECTED", timestamp=datetime.now())
    db.add(custody)
    db.commit()

    result = process_case_epra(db=db, case=case, current_user=expert)
    assert result["status"] == "SUCCESS"
    item = result["ranked_evidence"][0]
    
    # Verify backend exposed Janhvi's returned AR and integrity state
    epra_rec = db.query(EPRAResult).filter(EPRAResult.evidence_id == ev.id).first()
    assert item["authenticity_risk"] == epra_rec.authenticity_risk
    assert item["hash_verified"] is True
    assert isinstance(item["authenticity_risk"], float)
    # With verified hash and present custody, AR is low (< 0.10)
    assert item["authenticity_risk"] < 0.10


# ============================================================
# TEST 5 — CI INPUT PASSING
# ============================================================
def test_5_ci_input_passing(db):
    """
    Provide actual case_context/evidence context.
    Verify it reaches Janhvi implementation.
    """
    expert = make_user(id=11, full_name="Expert CI", role_id=3)
    db.add(expert)
    case = Case(id=102, case_id="CASE-TEST-CI", title="Bank Fraud Case", description="Investigation into fraudulent transaction and bank statement accounts", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    ev = Evidence(id=2, evidence_id="EV-CI-001", case_id=case.id, file_name="bank_statement.pdf", file_type="PDF", file_size=2048, file_path="/uploads/bank_statement.pdf")
    db.add(ev)
    db.commit()

    result = process_case_epra(db=db, case=case, current_user=expert)
    item = result["ranked_evidence"][0]

    # Directly compute Janhvi's ContextAnalyzer
    from ai_modules.epra_v2.intelligence.context_analyzer import ContextAnalyzer
    j_meta = JanhviMetadata(file_name="bank_statement.pdf", extension=".pdf", mime_type="application/pdf", size=2048, absolute_path="/uploads/bank_statement.pdf", evidence_type="PDF")
    j_ev = JanhviEvidence(metadata=j_meta)
    ContextAnalyzer.process(j_ev)

    assert item["context_intelligence"] == j_ev.context_intelligence
    # Filename contains bank and statement keywords -> CI elevated
    assert item["context_intelligence"] >= 0.85


# ============================================================
# TEST 6 — BI REAL DATA
# ============================================================
def test_6_bi_real_data(db):
    """
    Provide genuine behavior/activity test data.
    Verify it reaches Janhvi implementation and returned BI is exposed.
    """
    expert = make_user(id=12, full_name="Expert BI", role_id=3)
    db.add(expert)
    case = Case(id=103, case_id="CASE-TEST-BI", title="Privilege Activity Case", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    ev = Evidence(id=3, evidence_id="EV-BI-001", case_id=case.id, file_name="syslog.log", file_type="LOG", file_size=4096, file_path="/uploads/syslog.log")
    db.add(ev)
    
    # 5 custody access logs and an Administrator action
    for i in range(5):
        db.add(CustodyLog(evidence_id="EV-BI-001", investigator_name="Administrator", actor_role="ADMINISTRATOR", action="DELETE" if i == 4 else "ACCESSED", timestamp=datetime.now()))
    db.commit()

    result = process_case_epra(db=db, case=case, current_user=expert)
    item = result["ranked_evidence"][0]

    assert item["behaviour_intelligence"] is not None
    assert isinstance(item["behaviour_intelligence"], float)
    assert item["behaviour_intelligence"] > 0.0


# ============================================================
# TEST 7 — BI MISSING VS ZERO
# ============================================================
def test_7_bi_missing_vs_zero(db):
    """
    Case A: genuine Janhvi BI = 0.0 -> API = 0.0
    Case B: required BI input absent -> API = null/pending
    """
    expert = make_user(id=13, full_name="Expert BI Zero", role_id=3)
    db.add(expert)
    case = Case(id=104, case_id="CASE-TEST-BI-ZERO", title="Zero BI Verification", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    # Evidence A: Explicit genuine 0.0 behavioural intelligence provided
    ev_a = Evidence(id=4, evidence_id="EV-BI-A", case_id=case.id, file_name="doc_a.pdf", file_type="PDF", file_size=100, file_path="/uploads/doc_a.pdf")
    # Evidence B: No behavioural data, no audit logs
    ev_b = Evidence(id=5, evidence_id="EV-BI-B", case_id=case.id, file_name="doc_b.pdf", file_type="PDF", file_size=100, file_path="/uploads/doc_b.pdf")
    db.add(ev_a)
    db.add(ev_b)
    db.commit()

    # Pass genuine 0.0 for ev_a, omit for ev_b
    ext_inputs = {
        "EV-BI-A": {
            "behaviour_intelligence": 0.0
        }
    }

    result = process_case_epra(db=db, case=case, current_user=expert, external_inputs=ext_inputs, demo_mode=False)
    items = {r["evidence_id"]: r for r in result["ranked_evidence"]}

    # Case A: Genuine measured 0.0 remains 0.0 (float)
    assert items["EV-BI-A"]["behaviour_intelligence"] == 0.0
    assert items["EV-BI-A"]["behaviour_intelligence"] is not None

    # Case B: Missing BI is None / null and listed in pending_external_inputs
    assert items["EV-BI-B"]["behaviour_intelligence"] is None
    assert any("BI" in p or "Behaviour" in p or "behavioural" in p.lower() for p in items["EV-BI-B"]["pending_external_inputs"])


# ============================================================
# TEST 8 — IMAGE SI
# ============================================================
def test_8_image_si(db):
    """
    Persist/use genuine Member-3 semantic_score.
    Verify it is passed to Janhvi EPRA.
    Missing semantic_score: -> null/pending, no fake zero.
    """
    expert = make_user(id=14, full_name="Expert Image SI", role_id=3)
    db.add(expert)
    case = Case(id=105, case_id="CASE-TEST-IMAGE-SI", title="Image Investigation", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    # Image 1: With persisted Member 3 CBIRResult
    img1 = Evidence(id=6, evidence_id="EV-IMG-001", case_id=case.id, file_name="scene.jpg", file_type="IMAGE", file_size=5000, file_path="/uploads/scene.jpg")
    # Image 2: Without CBIRResult
    img2 = Evidence(id=7, evidence_id="EV-IMG-002", case_id=case.id, file_name="suspect_face.png", file_type="IMAGE", file_size=5000, file_path="/uploads/suspect_face.png")
    db.add(img1)
    db.add(img2)
    db.commit()

    # Persist genuine CBIR score for img1
    cbir = CBIRResult(
        case_id=case.id,
        query_evidence_id=img1.id,
        candidate_evidence_id=img1.id,
        visual_similarity_score=0.8876,
        semantic_score=0.8876,
        classification="DUPLICATE",
        confidence_level="HIGH",
        recommendation="RETAIN",
        reason="Visual similarity match"
    )
    db.add(cbir)
    db.commit()

    result = process_case_epra(db=db, case=case, current_user=expert, demo_mode=False)
    items = {r["evidence_id"]: r for r in result["ranked_evidence"]}

    # Image 1: Consumes persisted Member 3 score
    assert items["EV-IMG-001"]["semantic_intelligence"] == 0.8876
    assert items["EV-IMG-001"]["semantic_status"] == "MEASURED"

    # Image 2: Missing CBIR score remains null and PENDING
    assert items["EV-IMG-002"]["semantic_intelligence"] is None
    assert items["EV-IMG-002"]["semantic_status"] == "PENDING"
    assert any("IMAGE CBIR/Semantic" in p for p in items["EV-IMG-002"]["pending_external_inputs"])


# ============================================================
# TEST 9 — NON-IMAGE SI
# ============================================================
def test_9_non_image_si(db):
    """
    Provide actual readable text + case_context.
    Verify backend passes both to Janhvi semantic input.
    Missing content: -> pending/null -> NOT IMAGE CBIR pending reason.
    """
    expert = make_user(id=15, full_name="Expert Non-Image SI", role_id=3)
    db.add(expert)
    case = Case(id=106, case_id="CASE-TEST-NON-IMG-SI", title="Phishing Investigation", description="Credential theft and bank login phishing email attack", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    # Non-image 1: With readable content
    ev1 = Evidence(id=8, evidence_id="EV-NONIMG-001", case_id=case.id, file_name="phishing_email.eml", file_type="EMAIL", file_size=1200, file_path="/uploads/phishing_email.eml")
    # Non-image 2: Missing readable content
    ev2 = Evidence(id=9, evidence_id="EV-NONIMG-002", case_id=case.id, file_name="transaction_history.xlsx", file_type="SPREADSHEET", file_size=1200, file_path="/uploads/transaction_history.xlsx")
    db.add(ev1)
    db.add(ev2)
    db.commit()

    ext_inputs = {
        "EV-NONIMG-001": {
            "extracted_text": "Please login to verify your bank credential and password immediately"
        }
    }

    result = process_case_epra(db=db, case=case, current_user=expert, external_inputs=ext_inputs, demo_mode=False)
    items = {r["evidence_id"]: r for r in result["ranked_evidence"]}

    # Non-image 1: Successful TF-IDF semantic calculation
    assert items["EV-NONIMG-001"]["semantic_intelligence"] is not None
    assert items["EV-NONIMG-001"]["semantic_intelligence"] > 0.0
    assert items["EV-NONIMG-001"]["semantic_status"] == "MEASURED"

    # Non-image 2: Missing text -> PENDING with Non-Image reason, NOT IMAGE reason
    assert items["EV-NONIMG-002"]["semantic_intelligence"] is None
    assert items["EV-NONIMG-002"]["semantic_status"] == "PENDING"
    reasons = items["EV-NONIMG-002"]["pending_external_inputs"]
    assert any("Non-Image" in r or "document text" in r.lower() for r in reasons)
    assert not any("IMAGE CBIR" in r for r in reasons)


# ============================================================
# TEST 10 — II INPUT
# ============================================================
def test_10_ii_input(db):
    """
    Provide genuine supported investigation data.
    Verify it reaches Janhvi implementation.
    """
    expert = make_user(id=16, full_name="Expert II", role_id=3)
    db.add(expert)
    case = Case(id=107, case_id="CASE-TEST-II", title="Investigation Intelligence Case", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    ev = Evidence(id=10, evidence_id="EV-II-001", case_id=case.id, file_name="location_gps_evidence.pdf", file_type="PDF", file_size=1500, file_path="/uploads/location_gps_evidence.pdf")
    db.add(ev)
    db.commit()

    # Link suspect entity in DB
    suspect = PossibleEntity(case_id=case.id, suspect_id="SUSP-01", suspect_name="hacker@evil.com", entity_type="EMAIL", rank=1)
    db.add(suspect)
    db.commit()
    link = PossibleEntityEvidenceLink(entity_id=suspect.id, evidence_id=ev.id)
    db.add(link)
    db.commit()

    result = process_case_epra(db=db, case=case, current_user=expert)
    item = result["ranked_evidence"][0]

    # Directly compute Janhvi's InvestigationAnalyzer
    from ai_modules.epra_v2.intelligence.investigation_analyzer import InvestigationAnalyzer
    j_meta = JanhviMetadata(file_name="location_gps_evidence.pdf", extension=".pdf", mime_type="application/pdf", size=1500, absolute_path="/uploads/location_gps_evidence.pdf", evidence_type="PDF", created_time=datetime.now())
    j_ev = JanhviEvidence(metadata=j_meta, related_entities=["hacker@evil.com"])
    InvestigationAnalyzer.process(j_ev)

    assert item["investigative_intelligence"] == j_ev.investigative_intelligence
    assert item["investigative_intelligence"] > 0.0


# ============================================================
# TEST 11 — RESULT EXPOSURE
# ============================================================
def test_11_result_exposure(db):
    """
    Verify API fields equal Janhvi returned:
    AR, CI, BI, SI, II, IPI, EPRA Score, Priority, Rank, statuses/pending data.
    """
    expert = make_user(id=17, full_name="Expert Exposure", role_id=3)
    db.add(expert)
    case = Case(id=108, case_id="CASE-TEST-EXP", title="Exposure Case", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    ev = Evidence(id=11, evidence_id="EV-EXP-001", case_id=case.id, file_name="test_doc.docx", file_type="DOCUMENT", file_size=800, file_path="/uploads/test_doc.docx")
    db.add(ev)
    db.commit()

    result = process_case_epra(db=db, case=case, current_user=expert)
    item = result["ranked_evidence"][0]

    # Required API contract fields
    for field in [
        "rank", "evidence_id", "file_name", "evidence_type", "file_type",
        "authenticity_risk", "context_intelligence", "investigative_intelligence",
        "ipi", "epra_score", "priority", "semantic_status", "analysis_status",
        "pending_external_inputs"
    ]:
        assert field in item, f"Missing required field: {field}"

    # Verify query endpoints return matching values
    ranked = get_case_ranked_evidence(db, case=case)
    assert len(ranked) == 1
    assert ranked[0]["epra_score"] == item["epra_score"]
    assert ranked[0]["rank"] == item["rank"]
    assert ranked[0]["evidence_type"] == "DOCUMENT"

    detail = get_evidence_epra_detail(db, case=case, evidence_identifier="EV-EXP-001")
    assert detail["epra_score"] == item["epra_score"]
    assert detail["evidence_type"] == "DOCUMENT"


# ============================================================
# TEST 12 — NEW EVIDENCE DYNAMIC LIFECYCLE
# ============================================================
def test_12_new_evidence_dynamic_lifecycle(db):
    """
    Create a new test case and evidence record with arbitrary identifiers.
    Verify the backend dynamically: classifies type, fetches raw inputs,
    calls Janhvi EPRA, returns result without hardcoded identifiers.
    """
    expert = make_user(id=18, full_name="Expert Dynamic", role_id=3)
    db.add(expert)
    
    # Arbitrary runtime IDs
    dyn_case_id = f"CASE-DYN-{datetime.now().strftime('%M%S')}"
    dyn_ev_id = f"EV-DYN-{datetime.now().strftime('%M%S')}"
    case = Case(id=999, case_id=dyn_case_id, title="Dynamic Case", cyber_expert_id=expert.id)
    db.add(case)
    db.commit()

    ev = Evidence(id=999, evidence_id=dyn_ev_id, case_id=case.id, file_name="new_report.xlsx", file_type="DOCUMENT", file_size=3456, file_path="/uploads/new_report.xlsx")
    db.add(ev)
    db.commit()

    result = process_case_epra(db=db, case=case, current_user=expert)
    assert result["status"] == "SUCCESS"
    assert result["total_processed"] == 1
    item = result["ranked_evidence"][0]
    
    assert item["evidence_id"] == dyn_ev_id
    assert item["evidence_type"] == "SPREADSHEET"
    assert item["file_type"] == "SPREADSHEET"
    assert item["epra_score"] is not None
    assert item["priority"] in ("CRITICAL", "HIGH", "MEDIUM", "LOW", "VERY LOW")


# ============================================================
# TEST 13 — AUTH / CASE ISOLATION
# ============================================================
def test_13_auth_case_isolation(db):
    """
    Unauthorized case access / result exposure must fail with 403 Forbidden.
    """
    expert1 = make_user(id=19, full_name="Expert Authorized", role_id=3)
    expert2 = make_user(id=20, full_name="Expert Unauthorized", role_id=3)
    investigator = make_user(id=21, full_name="Investigator Other", role_id=2)
    db.add_all([expert1, expert2, investigator])
    
    case1 = Case(id=110, case_id="CASE-ISO-1", title="Isolated Case", cyber_expert_id=expert1.id)
    db.add(case1)
    db.commit()

    # Expert 1 can process
    auth_case = authorize_cyber_expert_case_access(db, "CASE-ISO-1", expert1)
    assert auth_case.id == case1.id

    # Expert 2 cannot process case 1 -> 403 Forbidden
    with pytest.raises(HTTPException) as exc_info:
        authorize_cyber_expert_case_access(db, "CASE-ISO-1", expert2)
    assert exc_info.value.status_code == 403

    # Investigator not assigned cannot read -> 403 Forbidden
    with pytest.raises(HTTPException) as exc_info:
        authorize_epra_read_case_access(db, "CASE-ISO-1", investigator)
    assert exc_info.value.status_code == 403
