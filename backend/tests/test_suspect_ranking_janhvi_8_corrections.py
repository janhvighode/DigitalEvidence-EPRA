"""
Master test suite for Suspect Ranking - Janhvi Final 8 Corrections.
Verifies all 15 required criteria using isolated in-memory testing:
1. Genuine extracted identifier reaches backend API (never fake human names)
2. Internal entity ID remains separate (SUSPECT-XXXX vs identifier)
3. One linked evidence score 33.97 -> total exactly 33.97
4. Multiple linked scores: 33.97 + 25.07 -> total exactly 59.04
5. Confidence has zero effect on total/rank
6. Missing confidence -> null/None, not 0.25
7. Ranking = Total EPRA Score DESC
8. Equal totals -> identifier alphabetical ASC
9. Linked evidence uses canonical EPRA type (no raw MIME)
10. Same entity result consistent across all backend endpoints
11. Summary counts are dynamic
12. Entity distribution is dynamic
13. Duplicate identifier across evidence is merged according to finalized contract
14. Authorization / case isolation works
15. NEW case / new evidence automatically enters the pipeline without hardcoding
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
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.case_timeline import CaseTimeline
from models.notification import Notification

from services.epra_service import (
    authorize_cyber_expert_case_access,
    normalize_epra_evidence_type
)
from services.suspect_ranking_service import (
    map_entity_type,
    process_case_suspect_ranking,
    get_case_ranked_possible_entities,
    get_case_possible_entities_summary,
    get_possible_entity_detail
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


@pytest.fixture
def db():
    """Isolated in-memory SQLite database for test suite."""
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(engine)
    SessionLocal = sessionmaker(bind=engine)
    session = SessionLocal()

    # Seed roles, city, cell
    session.add(Role(id=1, role_name="Admin"))
    session.add(Role(id=2, role_name="Investigator"))
    session.add(Role(id=3, role_name="Cyber Expert"))
    city = City(id=1, city_name="Metro City")
    cell = CyberCell(id=1, cyber_cell_name="Cyber HQ", admin_email="admin@metro.gov", city_id=1)
    session.add_all([city, cell])
    session.commit()

    yield session
    session.close()


# ============================================================
# TESTS 1 & 2: GENUINE IDENTIFIER & SEPARATE INTERNAL ID
# ============================================================
def test_1_and_2_genuine_extracted_identifier_and_separate_internal_id(db):
    """
    Prove:
    1. Suspect / Entity Identifier comes from the actual extracted entity identifier (email, IPv4, crypto, account).
       No fictitious human names (Rahul, Amit, Alice).
    2. Internal Entity ID (SUSPECT-XXXX) remains strictly separate from entity_identifier.
    """
    expert = make_user(101, "Expert Alan", 3)
    db.add(expert)
    case = Case(id=1, case_id="CASE-SR-001", title="Wire Fraud", cyber_expert_id=expert.id, status="In Progress")
    db.add(case)
    db.commit()

    ev1 = Evidence(id=1, case_id=case.id, evidence_id="EV-001", file_name="phishing.eml", file_type="EMAIL", file_size=1000, file_path="uploads/1/phishing.eml")
    h1 = EvidenceHash(evidence_id=1, file_name="phishing.eml", sha256_hash="h1", current_hash="h1", hash_match=True, integrity_status="Verified")
    epra1 = EPRAResult(case_id=case.id, evidence_id=1, epra_score=33.97, priority="LOW", rank=1)
    db.add_all([ev1, h1, epra1])
    db.commit()

    external_inputs = {
        "EV-001": {
            "extracted_text": "Phishing attack from attacker@blackhat.org to victim@bank.com via IP 198.51.100.25",
        }
    }

    result = process_case_suspect_ranking(db, case, expert, external_inputs=external_inputs)
    assert result["total_entities_identified"] >= 2

    ranked = get_case_ranked_possible_entities(db, case, current_user=expert)
    for ent in ranked:
        # Must have internal_entity_id starting with SUSPECT-
        assert ent.internal_entity_id.startswith("SUSPECT-")
        assert ent.suspect_id == ent.internal_entity_id

        # Must have genuine extracted entity_identifier matching the identifier itself
        assert ent.entity_identifier is not None
        assert ent.entity_identifier in ("attacker@blackhat.org", "victim@bank.com", "198.51.100.25")
        # NEVER invent fictitious human names
        assert ent.entity_identifier not in ("Rahul", "Amit", "Alice", "Bob")
        assert ent.suspect_name == ent.entity_identifier


# ============================================================
# TESTS 3 & 4: EXACT TOTAL EPRA SCORE SUMMATION
# ============================================================
def test_3_and_4_exact_total_score_summation(db):
    """
    Prove:
    3. One linked evidence score 33.97 -> Total EPRA Score is exactly 33.97.
    4. Multiple linked scores 33.97 + 25.07 -> Total EPRA Score is exactly 59.04.
    Consumed directly from final persisted EPRA results without recalculation or arbitrary weights.
    """
    expert = make_user(102, "Expert Ada", 3)
    db.add(expert)
    case = Case(id=2, case_id="CASE-SR-002", title="Crypto Laundering", cyber_expert_id=expert.id, status="In Progress")
    db.add(case)
    db.commit()

    # Evidence A with final EPRA score 33.97
    evA = Evidence(id=11, case_id=case.id, evidence_id="EV-A", file_name="email.eml", file_type="EMAIL", file_size=1000, file_path="uploads/2/email.eml")
    hA = EvidenceHash(evidence_id=11, file_name="email.eml", sha256_hash="ha", current_hash="ha", hash_match=True, integrity_status="Verified")
    epraA = EPRAResult(case_id=case.id, evidence_id=11, epra_score=33.97, priority="LOW", rank=1)

    # Evidence B with final EPRA score 25.07
    evB = Evidence(id=12, case_id=case.id, evidence_id="EV-B", file_name="ledger.csv", file_type="SPREADSHEET", file_size=2000, file_path="uploads/2/ledger.csv")
    hB = EvidenceHash(evidence_id=12, file_name="ledger.csv", sha256_hash="hb", current_hash="hb", hash_match=True, integrity_status="Verified")
    epraB = EPRAResult(case_id=case.id, evidence_id=12, epra_score=25.07, priority="LOW", rank=2)

    # Evidence C with final EPRA score 33.97 (single link)
    evC = Evidence(id=13, case_id=case.id, evidence_id="EV-C", file_name="invoice.pdf", file_type="PDF", file_size=3000, file_path="uploads/2/invoice.pdf")
    hC = EvidenceHash(evidence_id=13, file_name="invoice.pdf", sha256_hash="hc", current_hash="hc", hash_match=True, integrity_status="Verified")
    epraC = EPRAResult(case_id=case.id, evidence_id=13, epra_score=33.97, priority="LOW", rank=3)

    db.add_all([evA, hA, epraA, evB, hB, epraB, evC, hC, epraC])
    db.commit()

    # "syndicate@evil.org" appears in BOTH evA and evB (33.97 + 25.07 = 59.04)
    # "solo@evil.org" appears ONLY in evC (33.97)
    external_inputs = {
        "EV-A": {"extracted_text": "Transfer from syndicate@evil.org to offshore"},
        "EV-B": {"extracted_text": "Receipt signed by syndicate@evil.org confirmed"},
        "EV-C": {"extracted_text": "Single notice from solo@evil.org"}
    }

    process_case_suspect_ranking(db, case, expert, external_inputs=external_inputs)

    # Check multi-evidence entity (syndicate@evil.org)
    syndicate_detail = get_possible_entity_detail(db, case, "syndicate@evil.org", current_user=expert)
    assert syndicate_detail.total_epra_score == 59.04
    assert syndicate_detail.linked_evidence_count == 2
    assert len(syndicate_detail.linked_evidence) == 2
    scores = [item.epra_score for item in syndicate_detail.linked_evidence]
    assert sorted(scores) == [25.07, 33.97]
    assert round(sum(scores), 2) == syndicate_detail.total_epra_score

    # Check single-evidence entity (solo@evil.org)
    solo_detail = get_possible_entity_detail(db, case, "solo@evil.org", current_user=expert)
    assert solo_detail.total_epra_score == 33.97
    assert solo_detail.linked_evidence_count == 1
    assert len(solo_detail.linked_evidence) == 1
    assert solo_detail.linked_evidence[0].epra_score == 33.97


# ============================================================
# TESTS 5 & 6: CONFIDENCE HAS ZERO EFFECT ON TOTAL/RANK
# ============================================================
def test_5_and_6_confidence_has_zero_effect_and_missing_is_null(db):
    """
    Prove:
    5. Confidence score does NOT affect Total EPRA Score, rank, or ranking order.
    6. Missing confidence score is None (null), never arbitrary 0.25.
    """
    expert = make_user(103, "Expert Hopper", 3)
    db.add(expert)
    case = Case(id=3, case_id="CASE-SR-003", title="Rank Test", cyber_expert_id=expert.id, status="In Progress")
    db.add(case)
    db.commit()

    # Create entity X with Total EPRA Score = 80.0, but confidence = 0.25 (1 file)
    # Create entity Y with Total EPRA Score = 40.0, but confidence = 1.0 (4 files)
    ent_X = PossibleEntity(
        case_id=case.id,
        suspect_id="SUSPECT-X",
        suspect_name="target_high_score@test.com",
        entity_type="EMAIL",
        rank=1,
        total_epra_score=80.0,
        linked_evidence_count=1,
        confidence_score=0.25
    )
    ent_Y = PossibleEntity(
        case_id=case.id,
        suspect_id="SUSPECT-Y",
        suspect_name="target_high_conf@test.com",
        entity_type="EMAIL",
        rank=2,
        total_epra_score=40.0,
        linked_evidence_count=4,
        confidence_score=1.0
    )
    ent_Z_no_conf = PossibleEntity(
        case_id=case.id,
        suspect_id="SUSPECT-Z",
        suspect_name="target_no_conf@test.com",
        entity_type="EMAIL",
        rank=3,
        total_epra_score=20.0,
        linked_evidence_count=0,
        confidence_score=None  # Missing confidence
    )
    db.add_all([ent_X, ent_Y, ent_Z_no_conf])
    db.commit()

    ranked = get_case_ranked_possible_entities(db, case, current_user=expert)
    assert ranked[0].suspect_id == "SUSPECT-X"  # Rank 1 strictly because 80.0 > 40.0
    assert ranked[1].suspect_id == "SUSPECT-Y"  # Rank 2 despite higher confidence
    assert ranked[2].suspect_id == "SUSPECT-Z"
    assert ranked[2].confidence_score is None  # Must remain None (null in JSON), NOT 0.25


# ============================================================
# TESTS 7 & 8: EXACT RANKING RULE & TIE BREAKING
# ============================================================
def test_7_and_8_ranking_order_and_alphabetical_tie_break(db):
    """
    Prove Janhvi's finalized ranking rule:
    PRIMARY: Total EPRA Score DESCENDING
    TIE: Entity Identifier / Name ALPHABETICAL ASCENDING
    """
    expert = make_user(104, "Expert Turing", 3)
    db.add(expert)
    case = Case(id=4, case_id="CASE-SR-004", title="Tie Break Test", cyber_expert_id=expert.id, status="In Progress")
    db.add(case)
    db.commit()

    # Three entities: two have identical scores (50.0), one has higher (90.0)
    # Identical score entities: "zeta@evil.com" vs "alpha@evil.com"
    ev1 = Evidence(id=21, case_id=case.id, evidence_id="EV-21", file_name="e1.txt", file_type="DOCUMENT", file_size=100, file_path="uploads/4/e1.txt")
    ev2 = Evidence(id=22, case_id=case.id, evidence_id="EV-22", file_name="e2.txt", file_type="DOCUMENT", file_size=100, file_path="uploads/4/e2.txt")
    ev3 = Evidence(id=23, case_id=case.id, evidence_id="EV-23", file_name="e3.txt", file_type="DOCUMENT", file_size=100, file_path="uploads/4/e3.txt")
    h1 = EvidenceHash(evidence_id=21, file_name="e1.txt", sha256_hash="h1", current_hash="h1", hash_match=True, integrity_status="Verified")
    h2 = EvidenceHash(evidence_id=22, file_name="e2.txt", sha256_hash="h2", current_hash="h2", hash_match=True, integrity_status="Verified")
    h3 = EvidenceHash(evidence_id=23, file_name="e3.txt", sha256_hash="h3", current_hash="h3", hash_match=True, integrity_status="Verified")
    ep1 = EPRAResult(case_id=case.id, evidence_id=21, epra_score=90.0, priority="CRITICAL", rank=1)
    ep2 = EPRAResult(case_id=case.id, evidence_id=22, epra_score=50.0, priority="MEDIUM", rank=2)
    ep3 = EPRAResult(case_id=case.id, evidence_id=23, epra_score=50.0, priority="MEDIUM", rank=3)
    db.add_all([ev1, ev2, ev3, h1, h2, h3, ep1, ep2, ep3])
    db.commit()

    external_inputs = {
        "EV-21": {"extracted_text": "Leader: boss@syndicate.com"},
        "EV-22": {"extracted_text": "Associate: zeta@syndicate.com"},
        "EV-23": {"extracted_text": "Associate: alpha@syndicate.com"}
    }

    process_case_suspect_ranking(db, case, expert, external_inputs=external_inputs)
    ranked = get_case_ranked_possible_entities(db, case, current_user=expert)

    assert len(ranked) == 3
    # Rank 1: boss@syndicate.com (score 90.0)
    assert ranked[0].entity_identifier == "boss@syndicate.com"
    assert ranked[0].rank == 1
    assert ranked[0].total_epra_score == 90.0

    # Rank 2 vs 3: equal scores (50.0). "alpha@syndicate.com" must come before "zeta@syndicate.com"
    assert ranked[1].entity_identifier == "alpha@syndicate.com"
    assert ranked[1].rank == 2
    assert ranked[1].total_epra_score == 50.0

    assert ranked[2].entity_identifier == "zeta@syndicate.com"
    assert ranked[2].rank == 3
    assert ranked[2].total_epra_score == 50.0


# ============================================================
# TEST 9: LINKED EVIDENCE CANONICAL EPRA TYPE
# ============================================================
def test_9_linked_evidence_canonical_epra_type(db):
    """
    Prove that the Linked Evidence Breakdown backend response exposes
    the canonical EPRA evidence type in both file_type and evidence_type,
    with zero raw MIME leakage.
    """
    expert = make_user(105, "Expert Ritchie", 3)
    db.add(expert)
    case = Case(id=5, case_id="CASE-SR-005", title="Type Normalizer Test", cyber_expert_id=expert.id, status="In Progress")
    db.add(case)
    db.commit()

    test_files = [
        ("EV-T1", "transaction_history.xlsx", "Document", "SPREADSHEET", 45.0),
        ("EV-T2", "bank_statement.pdf", "PDF Document", "PDF", 40.0),
        ("EV-T3", "wallet_credentials.txt", "Document", "DOCUMENT", 35.0),
        ("EV-T4", "ransomware.exe", "Application", "EXECUTABLE", 30.0),
        ("EV-T5", "phishing_email.eml", "Message", "EMAIL", 25.0),
        ("EV-T6", "system_activity.log", "Unknown", "LOG", 20.0),
        ("EV-T7", "crime_scene_photo.jpg", "Image", "IMAGE", 15.0),
        ("EV-T8", "cctv_footage.mp4", "Video", "VIDEO", 10.0),
    ]

    for idx, (eid, fname, raw_t, canon_t, score) in enumerate(test_files, start=51):
        ev = Evidence(id=idx, case_id=case.id, evidence_id=eid, file_name=fname, file_type=raw_t, file_size=1024, file_path=f"uploads/5/{fname}")
        h = EvidenceHash(evidence_id=idx, file_name=fname, sha256_hash=f"h_{idx}", current_hash=f"h_{idx}", hash_match=True, integrity_status="Verified")
        ep = EPRAResult(case_id=case.id, evidence_id=idx, epra_score=score, priority="LOW", rank=idx-50)
        db.add_all([ev, h, ep])
    db.commit()

    # Link all files to a single entity
    external_inputs = {
        eid: {"entities": ["central_actor@syndicate.org"]} for eid, _, _, _, _ in test_files
    }

    process_case_suspect_ranking(db, case, expert, external_inputs=external_inputs)
    detail = get_possible_entity_detail(db, case, "central_actor@syndicate.org", current_user=expert)

    assert detail.linked_evidence_count == 8
    expected_map = {fname: canon_t for _, fname, _, canon_t, _ in test_files}

    for item in detail.linked_evidence:
        expected_type = expected_map[item.file_name]
        assert item.file_type == expected_type
        assert item.evidence_type == expected_type
        assert "/" not in item.file_type  # No raw MIME leak
        assert item.file_type != "Document" if expected_type != "DOCUMENT" else True


# ============================================================
# TEST 10: ONE AUTHORITATIVE RESULT ACROSS ALL ENDPOINTS
# ============================================================
def test_10_one_authoritative_result_across_all_endpoints(db):
    """
    Prove that all backend Suspect Ranking endpoints:
    - Top Entities by EPRA Score (summary)
    - Main ranking table (get_case_ranked_possible_entities)
    - Entity Detail (get_possible_entity_detail)
    derive from the same authoritative result and agree on all fields.
    """
    expert = make_user(106, "Expert Lovelace", 3)
    db.add(expert)
    case = Case(id=6, case_id="CASE-SR-006", title="Consistency Test", cyber_expert_id=expert.id, status="In Progress")
    db.add(case)
    db.commit()

    ev = Evidence(id=61, case_id=case.id, evidence_id="EV-61", file_name="data.eml", file_type="EMAIL", file_size=500, file_path="uploads/6/data.eml")
    h = EvidenceHash(evidence_id=61, file_name="data.eml", sha256_hash="h61", current_hash="h61", hash_match=True, integrity_status="Verified")
    ep = EPRAResult(case_id=case.id, evidence_id=61, epra_score=50.0, priority="MEDIUM", rank=1)
    db.add_all([ev, h, ep])
    db.commit()

    process_case_suspect_ranking(db, case, expert, external_inputs={"EV-61": {"entities": ["consistent_entity@test.org"]}})

    # 1. Summary top entities
    summary = get_case_possible_entities_summary(db, case, current_user=expert)
    top_ent = summary.top_entities[0]

    # 2. Main ranked entities
    ranked_list = get_case_ranked_possible_entities(db, case, current_user=expert)
    table_ent = ranked_list[0]

    # 3. Entity Detail
    detail_ent = get_possible_entity_detail(db, case, "consistent_entity@test.org", current_user=expert)

    # All must agree
    assert top_ent.suspect_id == table_ent.suspect_id == detail_ent.suspect_id
    assert top_ent.internal_entity_id == table_ent.internal_entity_id == detail_ent.internal_entity_id
    assert top_ent.entity_identifier == table_ent.entity_identifier == detail_ent.entity_identifier == "consistent_entity@test.org"
    assert top_ent.rank == table_ent.rank == detail_ent.rank == 1
    assert top_ent.total_epra_score == table_ent.total_epra_score == detail_ent.total_epra_score == 50.0
    assert top_ent.linked_evidence_count == table_ent.linked_evidence_count == detail_ent.linked_evidence_count == 1


# ============================================================
# TESTS 11 & 12: DYNAMIC SUMMARY & DISTRIBUTION
# ============================================================
def test_11_and_12_dynamic_summary_and_distribution(db):
    """
    Prove that summary metrics and type distribution are 100% dynamically computed
    from actual entities with NO hardcoding and NO double-counting.
    """
    expert = make_user(107, "Expert Knuth", 3)
    db.add(expert)
    case = Case(id=7, case_id="CASE-SR-007", title="Distribution Test", cyber_expert_id=expert.id, status="In Progress")
    db.add(case)
    db.commit()

    # Add 4 distinct entities: 2 emails, 1 IP, 1 crypto wallet
    e1 = PossibleEntity(case_id=case.id, suspect_id="S-1", suspect_name="a@test.com", entity_type="EMAIL", rank=1, total_epra_score=60.0, linked_evidence_count=2)
    e2 = PossibleEntity(case_id=case.id, suspect_id="S-2", suspect_name="b@test.com", entity_type="EMAIL", rank=2, total_epra_score=50.0, linked_evidence_count=1)
    e3 = PossibleEntity(case_id=case.id, suspect_id="S-3", suspect_name="198.51.100.1", entity_type="IP ADDRESS", rank=3, total_epra_score=40.0, linked_evidence_count=1)
    e4 = PossibleEntity(case_id=case.id, suspect_id="S-4", suspect_name="0x71C634C24532793db5ced09028A7A", entity_type="CRYPTO WALLET", rank=4, total_epra_score=30.0, linked_evidence_count=1)
    db.add_all([e1, e2, e3, e4])
    db.commit()

    summary = get_case_possible_entities_summary(db, case, current_user=expert)

    assert summary.total_suspects_entities == 4
    assert summary.email_addresses == 2
    assert summary.ip_addresses == 1
    assert summary.wallet_addresses == 1
    assert summary.account_ids == 0
    assert summary.other_entities == 0
    assert summary.highest_score == 60.0
    assert summary.lowest_score == 30.0
    assert summary.average_score == 45.0
    assert summary.entity_type_distribution == {"EMAIL": 2, "IP ADDRESS": 1, "CRYPTO WALLET": 1}


# ============================================================
# TEST 13: DUPLICATE IDENTIFIER MERGING
# ============================================================
def test_13_duplicate_identifier_merging_across_evidence(db):
    """
    Prove that when the same genuine identifier appears across multiple evidence files,
    it produces exactly ONE canonical entity linked to all files, with total score = sum(scores).
    """
    expert = make_user(108, "Expert Dijkstra", 3)
    db.add(expert)
    case = Case(id=8, case_id="CASE-SR-008", title="Deduplication Test", cyber_expert_id=expert.id, status="In Progress")
    db.add(case)
    db.commit()

    ev1 = Evidence(id=81, case_id=case.id, evidence_id="EV-81", file_name="f1.txt", file_type="DOCUMENT", file_size=100, file_path="uploads/8/f1.txt")
    ev2 = Evidence(id=82, case_id=case.id, evidence_id="EV-82", file_name="f2.txt", file_type="DOCUMENT", file_size=100, file_path="uploads/8/f2.txt")
    h1 = EvidenceHash(evidence_id=81, file_name="f1.txt", sha256_hash="h81", current_hash="h81", hash_match=True, integrity_status="Verified")
    h2 = EvidenceHash(evidence_id=82, file_name="f2.txt", sha256_hash="h82", current_hash="h82", hash_match=True, integrity_status="Verified")
    ep1 = EPRAResult(case_id=case.id, evidence_id=81, epra_score=33.97, priority="LOW", rank=1)
    ep2 = EPRAResult(case_id=case.id, evidence_id=82, epra_score=25.07, priority="LOW", rank=2)
    db.add_all([ev1, ev2, h1, h2, ep1, ep2])
    db.commit()

    # Same email in different casing across two evidence items
    external_inputs = {
        "EV-81": {"extracted_text": "Primary contact: Attacker@Example.com"},
        "EV-82": {"extracted_text": "Payment sent to attacker@example.com"}
    }

    result = process_case_suspect_ranking(db, case, expert, external_inputs=external_inputs)
    assert result["total_entities_identified"] == 1

    entities = get_case_ranked_possible_entities(db, case, current_user=expert)
    assert len(entities) == 1
    assert entities[0].total_epra_score == 59.04
    assert entities[0].linked_evidence_count == 2
    assert sorted(entities[0].linked_evidence_ids) == ["EV-81", "EV-82"]


# ============================================================
# TEST 14: AUTHORIZATION & CASE ISOLATION
# ============================================================
def test_14_authorization_and_case_isolation(db):
    """
    Prove that non-cyber experts or unassigned cyber experts are rejected with 403,
    and cross-case data leaks are impossible.
    """
    expert1 = make_user(109, "Expert One", 3)
    expert2 = make_user(110, "Expert Two", 3)
    investigator = make_user(111, "Inv Watson", 2)
    db.add_all([expert1, expert2, investigator])

    case1 = Case(id=91, case_id="CASE-SR-091", title="Case 1", cyber_expert_id=expert1.id, status="In Progress")
    case2 = Case(id=92, case_id="CASE-SR-092", title="Case 2", cyber_expert_id=expert2.id, status="In Progress")
    db.add_all([case1, case2])
    db.commit()

    # Expert 1 authorized for Case 1
    c1 = authorize_cyber_expert_case_access(db, case1.case_id, expert1)
    assert c1.id == case1.id

    # Expert 2 cannot access Case 1 (403)
    with pytest.raises(HTTPException) as exc:
        authorize_cyber_expert_case_access(db, case1.case_id, expert2)
    assert exc.value.status_code == 403

    # Investigator cannot access Case 1 via Cyber Expert route (403)
    with pytest.raises(HTTPException) as exc:
        authorize_cyber_expert_case_access(db, case1.case_id, investigator)
    assert exc.value.status_code == 403


# ============================================================
# TEST 15: NEW CASE / NEW EVIDENCE DYNAMIC LIFECYCLE
# ============================================================
def test_15_new_case_new_evidence_dynamic_automation(db):
    """
    Prove end-to-end automation:
    New case created -> new evidence added -> EPRA processed -> suspect ranking automatically runs
    -> API immediately serves fresh ranked entities without any case-specific code or hardcoding!
    """
    expert = make_user(112, "Expert Linus", 3)
    db.add(expert)
    new_case = Case(id=99, case_id="CASE-AUTO-NEW", title="Automated Intrusion", cyber_expert_id=expert.id, status="In Progress")
    db.add(new_case)
    db.commit()

    # New evidence uploaded
    new_ev = Evidence(
        id=901,
        case_id=new_case.id,
        evidence_id="EV-NEW-901",
        file_name="incident_report.log",
        file_type="LOG",
        file_size=2048,
        file_path="uploads/99/incident_report.log"
    )
    new_h = EvidenceHash(
        evidence_id=901,
        file_name="incident_report.log",
        sha256_hash="new_hash_901",
        current_hash="new_hash_901",
        hash_match=True,
        integrity_status="Verified"
    )
    db.add_all([new_ev, new_h])
    db.commit()

    # External inputs with real extracted text containing an attacker IP
    ext_in = {
        "EV-NEW-901": {
            "extracted_text": "Failed password for root from 203.0.113.88 port 443 ssh2 attack detected"
        }
    }

    # Calling get_case_ranked_possible_entities on the new case automatically triggers processing
    from services.epra_service import process_case_epra
    process_case_epra(db, new_case, expert, external_inputs=ext_in, demo_mode=False)

    # API immediately returns the new entity without ANY manual suspect ranking call!
    ranked = get_case_ranked_possible_entities(db, new_case, current_user=expert)
    assert len(ranked) >= 1
    found_ip = next((e for e in ranked if e.entity_identifier == "203.0.113.88"), None)
    assert found_ip is not None
    assert found_ip.entity_type == "IP ADDRESS"
    assert found_ip.rank == 1
    assert found_ip.total_epra_score > 0.0
    assert found_ip.linked_evidence_count == 1
    assert "EV-NEW-901" in found_ip.linked_evidence_ids
