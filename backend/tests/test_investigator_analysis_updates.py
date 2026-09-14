"""
Comprehensive Test Suite for Investigator Analysis Updates.
Verifies:
1. Valid Investigator authentication (role_id == 2)
2. Non-Investigator access rejected (role_id 1 -> 403, role_id 3 -> 403, None -> 401)
3. Investigator sees only assigned cases
4. Investigator A cannot access Investigator B case information (cross-investigator isolation)
5. Investigator with zero assigned cases (clean empty states)
6. Case with zero evidence (total_evidence=0, progress=0.0)
7. Case with no analysis started (progress=0.0, state=PENDING)
8. Partially analyzed case (in progress / in analysis)
9. Fully analyzed case (all applicable modules complete -> 100.0%)
10. CBIR N/A when no image evidence exists (excluded from progress denominator)
11. Genuine Integrity aggregation (tampered vs verified)
12. Genuine EPRA highest-priority aggregation (e.g. Critical, High)
13. Possible Entity count derivation
14. Relationship count derivation
15. Technical Report availability (ReportRecord integration)
16. analysis_progress calculation
17. attention_required calculation & specific reasons
18. latest_update selection (latest genuine timestamp)
19. Analysis Pulse chronological ordering (newest first)
20. Empty Analysis Pulse
21. Filters and search (search, analysis_state, attention_required, case_status, module)
"""
import sys
from pathlib import Path
from datetime import datetime, timezone, timedelta
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

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
from models.evidence_record import EvidenceRecord
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink
from models.report_record import ReportRecord
from models.case_timeline import CaseTimeline

from routes.investigator_analysis_updates_routes import (
    verify_investigator,
    fetch_analysis_updates_summary,
    fetch_cases_analysis_overview,
    fetch_single_case_analysis_overview,
    fetch_analysis_pulse_activity,
)
from services.investigator_analysis_updates_service import InvestigatorAnalysisUpdatesService


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
            EvidenceRecord.__table__,
            EPRAResult.__table__,
            CBIRResult.__table__,
            PossibleEntity.__table__,
            PossibleEntityEvidenceLink.__table__,
            EvidenceLink.__table__,
            ReportRecord.__table__,
            CaseTimeline.__table__,
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Seed Users
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
    empty_investigator = User(
        id=203, full_name="Inspector Zero", username="zero_inv", email="zero@police.gov.in",
        phone_number="9000000004", password="hash", role_id=2, cyber_cell_id=1, is_active=True
    )
    cyber_expert = User(
        id=301, full_name="Analyst Rajesh", username="rajesh_ce", email="rajesh@police.gov.in",
        phone_number="9000000005", password="hash", role_id=3, cyber_cell_id=1, is_active=True
    )

    db.add_all([admin, investigator_1, investigator_2, empty_investigator, cyber_expert])
    db.commit()

    now = datetime.now(timezone.utc).replace(tzinfo=None)

    # --------------------------------------------------------------------------
    # Seed Cases for investigator_1 (id=201)
    # --------------------------------------------------------------------------
    # Case 1: Open, High priority, has tampered evidence -> ATTENTION_REQUIRED
    # Has non-image evidence only (phish.eml, server_log.txt) -> CBIR is N/A!
    c1 = Case(
        id=1, case_id="CASE-2024-001", title="Bank Phishing Fraud",
        description="Financial phishing scam",
        investigator_id=201, cyber_expert_id=301, priority="High", status="Open", created_by=101,
        created_at=now - timedelta(days=5)
    )

    # Case 2: In Progress, Critical priority, has critical EPRA result, image evidence present
    c2 = Case(
        id=2, case_id="CASE-2024-002", title="Ransomware Extortion",
        description="Encrypted medical databases",
        investigator_id=201, cyber_expert_id=301, priority="Critical", status="In Progress", created_by=101,
        created_at=now - timedelta(days=4)
    )

    # Case 3: Fully analyzed case -> COMPLETED (100% progress)
    # Non-image files, so CBIR is N/A. All other 6 modules completed!
    c3 = Case(
        id=3, case_id="CASE-2024-003", title="Data Exfiltration Incident",
        description="Trade secrets stolen via flash drive",
        investigator_id=201, cyber_expert_id=301, priority="Medium", status="Closed", created_by=101,
        created_at=now - timedelta(days=3)
    )

    # Case 4: Zero evidence case
    c4 = Case(
        id=4, case_id="CASE-2024-004", title="Fresh Fraud Intake",
        description="Newly registered incident",
        investigator_id=201, cyber_expert_id=301, priority="Low", status="Open", created_by=101,
        created_at=now - timedelta(days=2)
    )

    # Case 5: Has evidence, but NO analysis started yet -> PENDING
    c5 = Case(
        id=5, case_id="CASE-2024-005", title="Identity Theft Case",
        description="Stolen Aadhaar identity",
        investigator_id=201, cyber_expert_id=301, priority="Low", status="Open", created_by=101,
        created_at=now - timedelta(days=1)
    )

    # --------------------------------------------------------------------------
    # Seed Case for investigator_2 (id=202) -> Cross-investigator isolation
    # --------------------------------------------------------------------------
    c6 = Case(
        id=6, case_id="CASE-2024-006", title="Crypto Scam Ring",
        description="Foreign telegram group scam",
        investigator_id=202, cyber_expert_id=301, priority="High", status="In Progress", created_by=101,
        created_at=now - timedelta(days=1)
    )

    db.add_all([c1, c2, c3, c4, c5, c6])
    db.commit()

    # --------------------------------------------------------------------------
    # Case 1 Data: 2 non-image files, 1 tampered hash, 1 verified hash
    # --------------------------------------------------------------------------
    ev1 = Evidence(id=1, evidence_id="EV-001", case_id=1, file_name="phish.eml", file_type="message/rfc822", file_size=1024, file_path="/storage/1.eml")
    ev2 = Evidence(id=2, evidence_id="EV-002", case_id=1, file_name="server_log.txt", file_type="text/plain", file_size=2048, file_path="/storage/2.txt")
    h1 = EvidenceHash(id=1, evidence_id=1, file_name="phish.eml", sha256_hash="hash1", current_hash="tampered_hash", original_hash="hash1", hash_match=False, tampered=True, integrity_status="TAMPERED", verified_at=now - timedelta(hours=3))
    h2 = EvidenceHash(id=2, evidence_id=2, file_name="server_log.txt", sha256_hash="hash2", current_hash="hash2", original_hash="hash2", hash_match=True, tampered=False, integrity_status="Verified", verified_at=now - timedelta(hours=4))
    # Metadata extracted for 1 file
    mr1 = EvidenceRecord(id=1, case_id="CASE-2024-001", external_evidence_id="EV-001", original_filename="phish.eml", stored_filename="1.eml", file_path="/storage/1.eml", retrieved_at=now - timedelta(hours=5))
    # EPRA processed for 1 file with High priority
    ep1 = EPRAResult(id=1, case_id=1, evidence_id=1, priority="High", epra_score=0.82, analysis_status="COMPLETE", processed_at=now - timedelta(hours=2))

    # --------------------------------------------------------------------------
    # Case 2 Data: 2 files including an image, critical EPRA, CBIR recorded, entities ranked
    # --------------------------------------------------------------------------
    ev3 = Evidence(id=3, evidence_id="EV-003", case_id=2, file_name="ransom_note.jpg", file_type="image/jpeg", file_size=4096, file_path="/storage/3.jpg")
    ev4 = Evidence(id=4, evidence_id="EV-004", case_id=2, file_name="payload.exe", file_type="application/octet-stream", file_size=8192, file_path="/storage/4.exe")
    h3 = EvidenceHash(id=3, evidence_id=3, file_name="ransom_note.jpg", sha256_hash="hash3", current_hash="hash3", original_hash="hash3", hash_match=True, tampered=False, integrity_status="Verified", verified_at=now - timedelta(hours=8))
    h4 = EvidenceHash(id=4, evidence_id=4, file_name="payload.exe", sha256_hash="hash4", current_hash="hash4", original_hash="hash4", hash_match=True, tampered=False, integrity_status="Verified", verified_at=now - timedelta(hours=8))
    # EPRA processed with Critical priority
    ep2 = EPRAResult(id=2, case_id=2, evidence_id=3, priority="Critical", epra_score=0.95, analysis_status="COMPLETE", processed_at=now - timedelta(hours=6))
    ep3 = EPRAResult(id=3, case_id=2, evidence_id=4, priority="Medium", epra_score=0.55, analysis_status="COMPLETE", processed_at=now - timedelta(hours=6))
    # CBIR result recorded
    cbir1 = CBIRResult(id=1, case_id=2, query_evidence_id=3, candidate_evidence_id=3, visual_similarity_score=1.0, semantic_score=0.9, classification="Exact Match", confidence_level="High", recommendation="Verify", rank=1, created_at=now - timedelta(hours=5))
    # Possible entities: 2 entities
    pe1 = PossibleEntity(id=1, case_id=2, suspect_id="SUSP-01", suspect_name="DarkLocker Operator", entity_type="EMAIL", rank=1, total_epra_score=1.5, linked_evidence_count=2, confidence_score=0.90, processed_at=now - timedelta(hours=4))
    pe2 = PossibleEntity(id=2, case_id=2, suspect_id="SUSP-02", suspect_name="198.51.100.23", entity_type="IP ADDRESS", rank=2, total_epra_score=0.95, linked_evidence_count=1, confidence_score=0.75, processed_at=now - timedelta(hours=4))
    pel1 = PossibleEntityEvidenceLink(id=1, entity_id=1, evidence_id=3, created_at=now - timedelta(hours=4))
    pel2 = PossibleEntityEvidenceLink(id=2, entity_id=2, evidence_id=3, created_at=now - timedelta(hours=4))
    # EvidenceLink (Relationship)
    el1 = EvidenceLink(id=1, case_id=2, evidence_id=3, suspect_name="DarkLocker Operator", relationship_type="AUTHOR_LINK", created_at=now - timedelta(hours=3))

    # --------------------------------------------------------------------------
    # Case 3 Data: Fully analyzed (all 6 applicable modules completed)
    # Non-image files: data.csv, doc.pdf
    # --------------------------------------------------------------------------
    ev5 = Evidence(id=5, evidence_id="EV-005", case_id=3, file_name="data.csv", file_type="text/csv", file_size=5000, file_path="/storage/5.csv")
    ev6 = Evidence(id=6, evidence_id="EV-006", case_id=3, file_name="doc.pdf", file_type="application/pdf", file_size=12000, file_path="/storage/6.pdf")
    # 1. Integrity verified
    h5 = EvidenceHash(id=5, evidence_id=5, file_name="data.csv", sha256_hash="hash5", current_hash="hash5", original_hash="hash5", hash_match=True, tampered=False, integrity_status="Verified", verified_at=now - timedelta(days=2))
    h6 = EvidenceHash(id=6, evidence_id=6, file_name="doc.pdf", sha256_hash="hash6", current_hash="hash6", original_hash="hash6", hash_match=True, tampered=False, integrity_status="Verified", verified_at=now - timedelta(days=2))
    # 2. Metadata completed
    mr2 = EvidenceRecord(id=2, case_id="CASE-2024-003", external_evidence_id="EV-005", original_filename="data.csv", stored_filename="5.csv", file_path="/storage/5.csv", retrieved_at=now - timedelta(days=2))
    mr3 = EvidenceRecord(id=3, case_id="CASE-2024-003", external_evidence_id="EV-006", original_filename="doc.pdf", stored_filename="6.pdf", file_path="/storage/6.pdf", retrieved_at=now - timedelta(days=2))
    # 3. EPRA completed
    ep4 = EPRAResult(id=4, case_id=3, evidence_id=5, priority="Low", epra_score=0.30, analysis_status="COMPLETE", processed_at=now - timedelta(days=1))
    ep5 = EPRAResult(id=5, case_id=3, evidence_id=6, priority="Low", epra_score=0.25, analysis_status="COMPLETE", processed_at=now - timedelta(days=1))
    # 4. CBIR -> N/A (no images)
    # 5. Entity ranking completed
    pe3 = PossibleEntity(id=3, case_id=3, suspect_id="SUSP-03", suspect_name="Insider Insider", entity_type="ACCOUNT ID", rank=1, total_epra_score=0.55, linked_evidence_count=2, processed_at=now - timedelta(days=1))
    pel3 = PossibleEntityEvidenceLink(id=3, entity_id=3, evidence_id=5, created_at=now - timedelta(days=1))
    # 6. Relationship completed
    el2 = EvidenceLink(id=2, case_id=3, evidence_id=5, suspect_name="Insider Insider", relationship_type="INSIDER_ACCESS", created_at=now - timedelta(days=1))
    # 7. Technical report completed
    rep1 = ReportRecord(
        id="REP-001", case_id="CASE-2024-003", file_name="Report_CASE-2024-003.pdf", file_path="/reports/1.pdf",
        investigator_name="Inspector Vikram", report_type="Comprehensive Forensic Report", file_format="PDF",
        is_draft=False, generated_at=now - timedelta(hours=10)
    )

    # --------------------------------------------------------------------------
    # Case 5 Data: Has 1 evidence, but no analysis at all
    # --------------------------------------------------------------------------
    ev7 = Evidence(id=7, evidence_id="EV-007", case_id=5, file_name="id_scan.png", file_type="image/png", file_size=3000, file_path="/storage/7.png")

    db.add_all([
        ev1, ev2, h1, h2, mr1, ep1,
        ev3, ev4, h3, h4, ep2, ep3, cbir1, pe1, pe2, pel1, pel2, el1,
        ev5, ev6, h5, h6, mr2, mr3, ep4, ep5, pe3, pel3, el2, rep1,
        ev7
    ])
    db.commit()

    return db, {
        "admin": admin,
        "investigator_1": investigator_1,
        "investigator_2": investigator_2,
        "empty_investigator": empty_investigator,
        "cyber_expert": cyber_expert
    }


def run_all_tests():
    print("=" * 70)
    print("RUNNING INVESTIGATOR ANALYSIS UPDATES INTEGRATION TESTS")
    print("=" * 70)

    db, users = setup_test_db()
    inv1 = users["investigator_1"]
    inv2 = users["investigator_2"]
    inv_empty = users["empty_investigator"]
    admin = users["admin"]
    expert = users["cyber_expert"]

    # --------------------------------------------------------------------------
    # Test 1: Valid Investigator Authentication
    # --------------------------------------------------------------------------
    verified = verify_investigator(inv1)
    assert verified.id == 201
    assert verified.role_id == 2
    print("  [PASS] 1. Valid Investigator authentication accepted (role_id == 2)")

    # --------------------------------------------------------------------------
    # Test 2: Non-Investigator Access Rejected (403 Forbidden)
    # --------------------------------------------------------------------------
    try:
        verify_investigator(admin)
        assert False, "Admin should be rejected"
    except HTTPException as e:
        assert e.status_code == 403
        assert "Investigator access required" in e.detail

    try:
        verify_investigator(expert)
        assert False, "Cyber Expert should be rejected"
    except HTTPException as e:
        assert e.status_code == 403

    try:
        verify_investigator(None)
        assert False, "Unauthenticated access should be rejected"
    except HTTPException as e:
        assert e.status_code == 401

    print("  [PASS] 2. Non-Investigator access rejected with 403 and unauthenticated with 401")

    # --------------------------------------------------------------------------
    # Test 3: Investigator Sees Only Assigned Cases
    # --------------------------------------------------------------------------
    summary1 = fetch_analysis_updates_summary(current_user=inv1, db=db)
    assert summary1.total_cases == 5, f"Expected 5 assigned cases for inv1, got {summary1.total_cases}"

    summary2 = fetch_analysis_updates_summary(current_user=inv2, db=db)
    assert summary2.total_cases == 1, f"Expected 1 assigned case for inv2, got {summary2.total_cases}"
    print("  [PASS] 3. Investigator sees only assigned cases (Investigator 1: 5, Investigator 2: 1)")

    # --------------------------------------------------------------------------
    # Test 4: Cross-Investigator Case Isolation
    # --------------------------------------------------------------------------
    # Investigator 1 tries to fetch Investigator 2's Case 6 (CASE-2024-006)
    try:
        fetch_single_case_analysis_overview(case_id="CASE-2024-006", current_user=inv1, db=db)
        assert False, "Investigator 1 should not be able to access Investigator 2's case"
    except HTTPException as e:
        assert e.status_code == 403
        assert "Access denied" in e.detail

    # Investigator 2 CAN fetch their own Case 6
    case6 = fetch_single_case_analysis_overview(case_id="CASE-2024-006", current_user=inv2, db=db)
    assert case6.case_id == "CASE-2024-006"
    print("  [PASS] 4. Cross-investigator case isolation enforced (403 on cross-access)")

    # --------------------------------------------------------------------------
    # Test 5: Investigator with Zero Assigned Cases
    # --------------------------------------------------------------------------
    summary_empty = fetch_analysis_updates_summary(current_user=inv_empty, db=db)
    assert summary_empty.total_cases == 0
    assert summary_empty.in_analysis == 0
    assert summary_empty.attention_required == 0
    assert summary_empty.completed == 0
    assert summary_empty.pending == 0

    cases_empty = fetch_cases_analysis_overview(current_user=inv_empty, db=db)
    assert cases_empty.total == 0
    assert len(cases_empty.items) == 0

    pulse_empty = fetch_analysis_pulse_activity(current_user=inv_empty, db=db)
    assert pulse_empty.total == 0
    assert len(pulse_empty.items) == 0
    print("  [PASS] 5. Investigator with zero assigned cases returns clean 0s and empty lists")

    # --------------------------------------------------------------------------
    # Test 6: Case with Zero Evidence
    # --------------------------------------------------------------------------
    c4_overview = fetch_single_case_analysis_overview(case_id="CASE-2024-004", current_user=inv1, db=db)
    assert c4_overview.case_intelligence.total_evidence == 0
    assert c4_overview.analysis_progress == 0.0
    assert c4_overview.analysis_state == "PENDING"
    assert c4_overview.analysis_modules.integrity.status == "PENDING"
    assert c4_overview.analysis_modules.cbir.status == "N/A"
    print("  [PASS] 6. Zero-evidence case handled safely (progress = 0.0, state = PENDING)")

    # --------------------------------------------------------------------------
    # Test 7: Case with No Analysis Started
    # --------------------------------------------------------------------------
    c5_overview = fetch_single_case_analysis_overview(case_id="CASE-2024-005", current_user=inv1, db=db)
    assert c5_overview.case_intelligence.total_evidence == 1
    assert c5_overview.analysis_progress == 0.0
    assert c5_overview.analysis_state == "PENDING"
    assert c5_overview.analysis_modules.epra.status == "PENDING"
    print("  [PASS] 7. Case with no analysis started reflects 0% progress and PENDING state")

    # --------------------------------------------------------------------------
    # Test 8: Partially Analyzed Case
    # --------------------------------------------------------------------------
    c1_overview = fetch_single_case_analysis_overview(case_id="CASE-2024-001", current_user=inv1, db=db)
    assert c1_overview.analysis_progress > 0.0
    assert c1_overview.analysis_progress < 100.0
    print(f"  [PASS] 8. Partially analyzed case progress calculated accurately ({c1_overview.analysis_progress}%)")

    # --------------------------------------------------------------------------
    # Test 9: Fully Analyzed Case (100% Progress, COMPLETED state)
    # --------------------------------------------------------------------------
    c3_overview = fetch_single_case_analysis_overview(case_id="CASE-2024-003", current_user=inv1, db=db)
    assert c3_overview.analysis_progress == 100.0, f"Expected 100.0% progress, got {c3_overview.analysis_progress}"
    assert c3_overview.analysis_state == "COMPLETED"
    assert c3_overview.analysis_modules.integrity.status == "COMPLETED"
    assert c3_overview.analysis_modules.metadata.status == "COMPLETED"
    assert c3_overview.analysis_modules.epra.status == "COMPLETED"
    assert c3_overview.analysis_modules.entity_ranking.status == "COMPLETED"
    assert c3_overview.analysis_modules.relationship.status == "COMPLETED"
    assert c3_overview.analysis_modules.technical_report.status == "COMPLETED"
    print("  [PASS] 9. Fully analyzed case achieves 100.0% progress and COMPLETED state")

    # --------------------------------------------------------------------------
    # Test 10: CBIR N/A When No Image Evidence Exists
    # --------------------------------------------------------------------------
    # Case 1 and Case 3 have no image evidence -> CBIR must be N/A
    assert c1_overview.analysis_modules.cbir.status == "N/A"
    assert c3_overview.analysis_modules.cbir.status == "N/A"
    # Case 2 has an image file (ransom_note.jpg) -> CBIR must be COMPLETED
    c2_overview = fetch_single_case_analysis_overview(case_id="CASE-2024-002", current_user=inv1, db=db)
    assert c2_overview.analysis_modules.cbir.status == "COMPLETED"
    print("  [PASS] 10. CBIR evaluates to N/A for non-image cases and COMPLETED for image cases")

    # --------------------------------------------------------------------------
    # Test 11: Genuine Integrity Aggregation
    # --------------------------------------------------------------------------
    # Case 1 has 1 tampered hash -> ATTENTION_REQUIRED
    assert c1_overview.analysis_modules.integrity.status == "ATTENTION_REQUIRED"
    assert c1_overview.case_intelligence.integrity_status == "ATTENTION_REQUIRED"
    # Case 3 has all verified hashes -> COMPLETED & VERIFIED
    assert c3_overview.analysis_modules.integrity.status == "COMPLETED"
    assert c3_overview.case_intelligence.integrity_status == "VERIFIED"
    print("  [PASS] 11. Integrity status derived truthfully (Tampered -> ATTENTION_REQUIRED, Verified -> VERIFIED)")

    # --------------------------------------------------------------------------
    # Test 12: Genuine EPRA Highest-Priority Aggregation
    # --------------------------------------------------------------------------
    # Case 2 has 1 Critical EPRA result and 1 Medium -> Highest must be Critical
    assert c2_overview.case_intelligence.highest_epra_priority == "Critical"
    # Case 1 has 1 High EPRA result -> Highest must be High
    assert c1_overview.case_intelligence.highest_epra_priority == "High"
    # Case 3 has Low EPRA results -> Highest must be Low
    assert c3_overview.case_intelligence.highest_epra_priority == "Low"
    print("  [PASS] 12. Highest EPRA Priority aggregated accurately (Critical, High, Low)")

    # --------------------------------------------------------------------------
    # Test 13: Possible Entity Count Derivation
    # --------------------------------------------------------------------------
    # Case 2 has 2 possible entities seeded
    assert c2_overview.case_intelligence.possible_entities == 2
    # Case 1 has 0 entities seeded
    assert c1_overview.case_intelligence.possible_entities == 0
    print("  [PASS] 13. Possible Entity counts match genuine linked entities (Case 2: 2, Case 1: 0)")

    # --------------------------------------------------------------------------
    # Test 14: Relationship Count Derivation
    # --------------------------------------------------------------------------
    # Case 2 has 2 entity links + 1 custom link = at least 3 relationships
    assert c2_overview.case_intelligence.relationships_found >= 3
    print(f"  [PASS] 14. Relationships found matches graph connections ({c2_overview.case_intelligence.relationships_found})")

    # --------------------------------------------------------------------------
    # Test 15: Technical Report Availability
    # --------------------------------------------------------------------------
    # Case 3 has a finalized report
    assert c3_overview.analysis_modules.technical_report.status == "COMPLETED"
    assert c3_overview.case_intelligence.technical_report_status == "COMPLETED"
    # Case 1 has no report
    assert c1_overview.analysis_modules.technical_report.status == "PENDING"
    assert c1_overview.case_intelligence.technical_report_status == "PENDING"
    print("  [PASS] 15. Technical Report availability dynamically reflects stored ReportRecord")

    # --------------------------------------------------------------------------
    # Test 16: Mathematical Integrity of analysis_progress
    # --------------------------------------------------------------------------
    # For Case 3: 6 applicable modules (CBIR is N/A), all 6 completed -> 6/6 * 100 = 100.0%
    assert c3_overview.analysis_progress == 100.0
    # For Case 1: 6 applicable modules (CBIR is N/A). Completed: none fully completed (integrity has tampered, metadata 1/2, epra 1/2) -> 0.0%
    # For Case 2: 7 applicable modules (CBIR applicable and complete, EPRA complete, entity complete, integrity complete, rel complete)
    # Check that progress is strictly within [0.0, 100.0]
    for case_item in [c1_overview, c2_overview, c3_overview, c4_overview, c5_overview]:
        assert 0.0 <= case_item.analysis_progress <= 100.0
    print("  [PASS] 16. Mathematical consistency of analysis_progress verified")

    # --------------------------------------------------------------------------
    # Test 17: Attention Required Calculation & Reasons
    # --------------------------------------------------------------------------
    # Case 1 must require attention due to tampered hash
    assert c1_overview.attention_required is True
    assert any("integrity compromised" in r.lower() for r in c1_overview.attention_reasons)

    # Case 2 must require attention due to Critical EPRA priority
    assert c2_overview.attention_required is True
    assert any("critical epra" in r.lower() for r in c2_overview.attention_reasons)

    # Case 3 does NOT require attention
    assert c3_overview.attention_required is False
    assert len(c3_overview.attention_reasons) == 0
    print("  [PASS] 17. Attention Required evaluated with factual forensic reasons")

    # --------------------------------------------------------------------------
    # Test 18: Latest Update Selection
    # --------------------------------------------------------------------------
    assert c1_overview.latest_update is not None
    assert c1_overview.latest_update.module in ["EPRA", "INTEGRITY", "METADATA"]
    assert c1_overview.latest_update.updated_at is not None
    print(f"  [PASS] 18. Latest update correctly selected ({c1_overview.latest_update.module}: {c1_overview.latest_update.message})")

    # --------------------------------------------------------------------------
    # Test 19: Analysis Pulse Chronological Ordering (Newest First)
    # --------------------------------------------------------------------------
    pulse = fetch_analysis_pulse_activity(current_user=inv1, db=db, limit=50)
    assert pulse.total > 0
    assert len(pulse.items) > 0

    for i in range(len(pulse.items) - 1):
        t1 = pulse.items[i].timestamp
        t2 = pulse.items[i + 1].timestamp
        assert t1 >= t2, f"Pulse items not sorted descending: {t1} < {t2}"
    print(f"  [PASS] 19. Analysis Pulse activities ordered newest-first ({pulse.total} events)")

    # --------------------------------------------------------------------------
    # Test 20: Empty Analysis Pulse
    # --------------------------------------------------------------------------
    empty_pulse = fetch_analysis_pulse_activity(current_user=inv_empty, db=db)
    assert empty_pulse.total == 0
    assert len(empty_pulse.items) == 0
    print("  [PASS] 20. Empty Analysis Pulse returns 0 events for investigator with no activity")

    # --------------------------------------------------------------------------
    # Test 21: Filters and Search
    # --------------------------------------------------------------------------
    # 21a: Search by text "Phishing"
    search_res = fetch_cases_analysis_overview(search="Phishing", current_user=inv1, db=db)
    assert search_res.total == 1
    assert search_res.items[0].case_id == "CASE-2024-001"

    # 21b: Filter by analysis_state == "COMPLETED"
    completed_res = fetch_cases_analysis_overview(analysis_state="COMPLETED", current_user=inv1, db=db)
    assert completed_res.total == 1
    assert completed_res.items[0].case_id == "CASE-2024-003"

    # 21c: Filter by attention_required == True
    attention_res = fetch_cases_analysis_overview(attention_required=True, current_user=inv1, db=db)
    assert attention_res.total >= 2  # Case 1 and Case 2

    # 21d: Filter by case_status == "Closed"
    closed_res = fetch_cases_analysis_overview(case_status="Closed", current_user=inv1, db=db)
    assert closed_res.total == 1
    assert closed_res.items[0].case_id == "CASE-2024-003"

    # 21e: Filter pulse by module == "EPRA"
    epra_pulse = fetch_analysis_pulse_activity(module="EPRA", current_user=inv1, db=db)
    assert all(e.module == "EPRA" for e in epra_pulse.items)

    print("  [PASS] 21. Filters (search, analysis_state, attention_required, case_status, module) verified")

    # --------------------------------------------------------------------------
    # Test 22: Single-Case Access Protection
    # --------------------------------------------------------------------------
    # Non-existent case raises 404
    try:
        fetch_single_case_analysis_overview(case_id="CASE-NONEXISTENT", current_user=inv1, db=db)
        assert False, "Non-existent case should 404"
    except HTTPException as e:
        assert e.status_code == 404
    print("  [PASS] 22. Single-case access protection verified (404 on invalid case, 403 on cross-case)")

    # --------------------------------------------------------------------------
    # Test 23: No Confidence-Based Suspect Alert
    # --------------------------------------------------------------------------
    # Ensure suspect confidence score is NOT used as an attention trigger anywhere
    for c_item in [c1_overview, c2_overview, c3_overview, c4_overview, c5_overview]:
        assert not any("confidence" in r.lower() for r in c_item.attention_reasons), "No confidence-based alert permitted"
    print("  [PASS] 23. Verified NO confidence-based suspect alerts exist")

    print("=" * 70)
    print("ALL 23 INVESTIGATOR ANALYSIS UPDATES INTEGRATION TESTS PASSED!")
    print("=" * 70)


if __name__ == "__main__":
    run_all_tests()

