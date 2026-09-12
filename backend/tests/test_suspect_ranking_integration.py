import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime

# Add project root and backend dir to sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException
from database.database import SessionLocal, engine, Base
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink

from ai_modules.epra_v2.models.evidence import Evidence as JanhviEvidence
from ai_modules.epra_v2.models.metadata import Metadata as JanhviMetadata
from ai_modules.epra_v2.intelligence.relationship_analyzer import RelationshipAnalyzer
from ai_modules.epra_v2.ranking.suspect_ranker import SuspectRanker
from ai_modules.epra_v2.models.suspect import Suspect

from services.epra_service import authorize_cyber_expert_case_access, process_case_epra
from services.suspect_ranking_service import (
    map_entity_type,
    process_case_suspect_ranking,
    get_case_ranked_possible_entities,
    get_case_possible_entities_summary,
    get_possible_entity_detail,
)
from routes.possible_entity_routes import router as possible_entity_router


def test_1_routes_registered_and_endpoints_correct():
    """Verify all 4 possible-entities routes are mounted with correct HTTP methods."""
    routes = {r.path: r.methods for r in possible_entity_router.routes}
    assert "/cases/{case_id}/possible-entities/process" in routes
    assert "POST" in routes["/cases/{case_id}/possible-entities/process"]

    assert "/cases/{case_id}/possible-entities" in routes
    assert "GET" in routes["/cases/{case_id}/possible-entities"]

    assert "/cases/{case_id}/possible-entities/summary" in routes
    assert "GET" in routes["/cases/{case_id}/possible-entities/summary"]

    assert "/cases/{case_id}/possible-entities/{entity_id}" in routes
    assert "GET" in routes["/cases/{case_id}/possible-entities/{entity_id}"]
    print("PASS: test_1_routes_registered_and_endpoints_correct")


def test_2_cyber_expert_authorization_and_case_scoping():
    """Verify role_id == 3 enforcement and case-scoped assignment security."""
    db = SessionLocal()
    try:
        # 1. Non-cyber expert role must be rejected with 403
        fake_user = User(id=7701, role_id=1, full_name="Admin User")
        try:
            authorize_cyber_expert_case_access(db, "C-9999", fake_user)
            assert False, "Must reject non-cyber expert"
        except HTTPException as e:
            assert e.status_code == 403
            assert "Cyber Expert access required" in e.detail

        # 2. Cyber expert accessing unassigned case must be rejected with 403
        expert = db.query(User).filter(User.role_id == 3).first()
        if not expert:
            expert = User(id=7702, role_id=3, full_name="Expert X", username="expert_x")
            db.add(expert)
            db.commit()

        unassigned_case = db.query(Case).filter(Case.cyber_expert_id != expert.id).first()
        if unassigned_case:
            try:
                authorize_cyber_expert_case_access(db, unassigned_case.id, expert)
                assert False, "Must reject unassigned cyber expert"
            except HTTPException as e:
                assert e.status_code == 403
                assert "Access denied" in e.detail

        # 3. Non-existent case must return 404
        try:
            authorize_cyber_expert_case_access(db, "NON_EXISTENT_CASE_9999", expert)
            assert False, "Must return 404"
        except HTTPException as e:
            assert e.status_code == 404
    finally:
        db.close()
    print("PASS: test_2_cyber_expert_authorization_and_case_scoping")


def test_3_safe_actor_extraction_and_transaction_isolation():
    """Verify genuine identifier extraction, no fake names, and transaction IDs excluded from suspects."""
    text = (
        "Investigation log:\n"
        "Suspect email: attacker@darknet.org\n"
        "Origin server IP: 198.51.100.23\n"
        "Payment sent to Bitcoin: bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh\n"
        "Account reference: ACC-994821\n"
        "Transaction ID: TXN-88492041\n"
        "Invoice Reference: INV-2026-9901\n"
    )
    actor_pairs = RelationshipAnalyzer.extract_actor_identifiers(text)
    tx_ids = RelationshipAnalyzer.extract_transaction_identifiers(text)

    # Verify actors extracted
    extracted_idents = [ident for _, ident in actor_pairs]
    assert "attacker@darknet.org" in extracted_idents
    assert "198.51.100.23" in extracted_idents
    assert "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh" in extracted_idents
    assert "ACC-994821" in extracted_idents

    # Verify transaction IDs are isolated and NOT actors
    assert "TXN-88492041" in tx_ids
    assert "INV-2026-9901" in tx_ids
    assert "TXN-88492041" not in extracted_idents
    assert "INV-2026-9901" not in extracted_idents

    # Verify type mapping
    assert map_entity_type("attacker@darknet.org") == "EMAIL"
    assert map_entity_type("198.51.100.23") == "IP ADDRESS"
    assert map_entity_type("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh") == "CRYPTO WALLET"
    assert map_entity_type("0x71C84517550E9F5b48B69f88C647C859cbfC8483") == "CRYPTO WALLET"
    assert map_entity_type("ACC-994821") == "ACCOUNT ID"
    assert map_entity_type("UnknownSubject") == "OTHER"

    # Verify NO fictitious names are fabricated
    for name in ["Rahul", "Amit", "Alice", "Bob", "John Doe"]:
        assert name not in extracted_idents
    print("PASS: test_3_safe_actor_extraction_and_transaction_isolation")


def test_4_suspect_ranking_scoring_and_tie_breaking():
    """Verify total EPRA score = SUM(linked evidence scores), rank order, and tie-breaking."""
    # Create fake evidence items with specific EPRA scores
    ev1 = JanhviEvidence(metadata=JanhviMetadata(evidence_id="EV-1", file_name="f1.txt", extension=".txt", mime_type="text/plain", size=10, absolute_path=""))
    ev1.epra_score = 45.0

    ev2 = JanhviEvidence(metadata=JanhviMetadata(evidence_id="EV-2", file_name="f2.txt", extension=".txt", mime_type="text/plain", size=10, absolute_path=""))
    ev2.epra_score = 35.0

    ev3 = JanhviEvidence(metadata=JanhviMetadata(evidence_id="EV-3", file_name="f3.txt", extension=".txt", mime_type="text/plain", size=10, absolute_path=""))
    ev3.epra_score = 45.0

    # Suspect A: linked to ev1 + ev2 => total 80.0
    s_a = Suspect(
        suspect_id="SUSPECT-A",
        suspect_name="zebra@evil.com",
        evidence_list=[ev1, ev2],
        confidence_score=0.9
    )

    # Suspect B: linked to ev1 + ev3 => total 90.0, lower confidence (0.2)
    s_b = Suspect(
        suspect_id="SUSPECT-B",
        suspect_name="beta@evil.com",
        evidence_list=[ev1, ev3],
        confidence_score=0.2  # Lower confidence MUST NOT lower ranking
    )

    # Suspect C: linked to ev1 + ev3 => total 90.0, name 'alpha@evil.com' (tie with B on score)
    s_c = Suspect(
        suspect_id="SUSPECT-C",
        suspect_name="alpha@evil.com",
        evidence_list=[ev1, ev3],
        confidence_score=0.5
    )

    ranked = SuspectRanker.rank([s_a, s_b, s_c])

    # Rule 1: Highest total score first (90.0 > 80.0)
    # Rule 2: Score tie between s_b ('beta') and s_c ('alpha') -> s_c ('alpha') ranks before s_b ('beta') alphabetically
    # Rule 3: Confidence score does NOT alter score or rank
    assert ranked[0].suspect_name == "alpha@evil.com"
    assert ranked[0].rank == 1
    assert ranked[0].total_epra_score == 90.0

    assert ranked[1].suspect_name == "beta@evil.com"
    assert ranked[1].rank == 2
    assert ranked[1].total_epra_score == 90.0

    assert ranked[2].suspect_name == "zebra@evil.com"
    assert ranked[2].rank == 3
    assert ranked[2].total_epra_score == 80.0
    print("PASS: test_4_suspect_ranking_scoring_and_tie_breaking")


def test_5_full_case_processing_and_relational_link_storage():
    """Verify processing case with real evidence, database persistence, and relational link table integrity."""
    db = SessionLocal()
    try:
        expert = db.query(User).filter(User.role_id == 3).first()
        if not expert:
            expert = User(id=7703, role_id=3, full_name="Expert Z", username="expert_z")
            db.add(expert)
            db.commit()

        # Create isolated test case
        case = db.query(Case).filter(Case.case_id == "TEST-SUSPECT-CASE-1").first()
        if not case:
            case = Case(
                case_id="TEST-SUSPECT-CASE-1",
                title="Ransomware Suspect Investigation",
                description="Case involving multiple communication logs and wallets",
                cyber_expert_id=expert.id,
                status="Open",
                priority="High"
            )
            db.add(case)
            db.commit()

        # Create temporary evidence files with real readable content
        test_dir = backend_dir / "uploads" / "evidence" / str(case.id)
        test_dir.mkdir(parents=True, exist_ok=True)

        file1_path = test_dir / "comm_log_1.txt"
        file1_path.write_text(
            "Log 1:\nContact attacker at operator@darknet.org\nHost: 198.51.100.50\nRef: TXN-0001",
            encoding="utf-8"
        )

        file2_path = test_dir / "comm_log_2.txt"
        file2_path.write_text(
            "Log 2:\nSecondary email: operator@darknet.org\nWallet: 0x71C84517550E9F5b48B69f88C647C859cbfC8483",
            encoding="utf-8"
        )

        # Create unreadable/binary evidence to test safe skipping without fabrication (Correction #3)
        file3_path = test_dir / "binary_data.bin"
        file3_path.write_bytes(b"\x00\x01\x02\x03\x04\xff\xfe\xfd")

        # Add evidence records to DB
        ev1 = db.query(Evidence).filter(Evidence.evidence_id == "EV-SUSP-001").first()
        if not ev1:
            ev1 = Evidence(
                evidence_id="EV-SUSP-001",
                case_id=case.id,
                file_name="comm_log_1.txt",
                file_type="Document",
                file_size=file1_path.stat().st_size,
                file_path=str(file1_path).replace("\\", "/"),
                status="Active"
            )
            db.add(ev1)

        ev2 = db.query(Evidence).filter(Evidence.evidence_id == "EV-SUSP-002").first()
        if not ev2:
            ev2 = Evidence(
                evidence_id="EV-SUSP-002",
                case_id=case.id,
                file_name="comm_log_2.txt",
                file_type="Document",
                file_size=file2_path.stat().st_size,
                file_path=str(file2_path).replace("\\", "/"),
                status="Active"
            )
            db.add(ev2)

        ev3 = db.query(Evidence).filter(Evidence.evidence_id == "EV-SUSP-003").first()
        if not ev3:
            ev3 = Evidence(
                evidence_id="EV-SUSP-003",
                case_id=case.id,
                file_name="binary_data.bin",
                file_type="Archive",
                file_size=file3_path.stat().st_size,
                file_path=str(file3_path).replace("\\", "/"),
                status="Active"
            )
            db.add(ev3)
        db.commit()

        # Run suspect ranking process
        res = process_case_suspect_ranking(db, case, expert)

        assert res["case_id"] == case.case_id
        assert res["total_entities_identified"] >= 3  # operator@darknet.org, 198.51.100.50, crypto wallet

        # Verify operator@darknet.org is linked to BOTH ev1 and ev2 (deduplication)
        operator_ent = next((e for e in res["ranked_entities"] if e.suspect_name == "operator@darknet.org"), None)
        assert operator_ent is not None, "operator@darknet.org must be extracted"
        assert operator_ent.linked_evidence_count == 2
        assert "EV-SUSP-001" in operator_ent.linked_evidence_ids
        assert "EV-SUSP-002" in operator_ent.linked_evidence_ids

        # Verify relational link table is populated (Correction #2)
        links = db.query(PossibleEntityEvidenceLink).filter(
            PossibleEntityEvidenceLink.entity_id == operator_ent.id
        ).all()
        assert len(links) == 2
        linked_db_ev_ids = [l.evidence_id for l in links]
        assert ev1.id in linked_db_ev_ids
        assert ev2.id in linked_db_ev_ids

        # Verify binary file extraction limitations note (Correction #3)
        assert res["limitations_note"] is not None
        assert "safely skipped without fabricating identifiers" in res["limitations_note"]

    finally:
        db.close()
    print("PASS: test_5_full_case_processing_and_relational_link_storage")


def test_6_idempotent_reprocessing_preserves_records_and_updates_links():
    """Verify re-processing is idempotent, updates in-place, and never uses clear/delete-all (Correction #1)."""
    db = SessionLocal()
    try:
        expert = db.query(User).filter(User.role_id == 3).first()
        case = db.query(Case).filter(Case.case_id == "TEST-SUSPECT-CASE-1").first()

        # Capture entity IDs before re-run
        before_entities = db.query(PossibleEntity).filter(PossibleEntity.case_id == case.id).all()
        before_id_map = {e.suspect_id: e.id for e in before_entities}
        assert len(before_id_map) > 0

        # Execute re-run
        res = process_case_suspect_ranking(db, case, expert)

        # Verify entity IDs are PRESERVED (no unsafe drop-and-recreate)
        after_entities = db.query(PossibleEntity).filter(PossibleEntity.case_id == case.id).all()
        after_id_map = {e.suspect_id: e.id for e in after_entities}

        for suspect_id, old_pk in before_id_map.items():
            assert suspect_id in after_id_map
            assert after_id_map[suspect_id] == old_pk, f"Entity PK {old_pk} should be preserved across idempotent re-runs"

        # Verify no duplicate links in possible_entity_evidence_links
        total_links = db.query(PossibleEntityEvidenceLink).join(PossibleEntity).filter(
            PossibleEntity.case_id == case.id
        ).count()
        distinct_links = db.query(
            PossibleEntityEvidenceLink.entity_id, PossibleEntityEvidenceLink.evidence_id
        ).join(PossibleEntity).filter(PossibleEntity.case_id == case.id).distinct().count()
        assert total_links == distinct_links, "No duplicate evidence links allowed"

        # Verify evidence, case, hashes, and EPRA results are NOT deleted
        assert db.query(Evidence).filter(Evidence.case_id == case.id).count() >= 3
        assert db.query(EPRAResult).filter(EPRAResult.case_id == case.id).count() >= 3

    finally:
        db.close()
    print("PASS: test_6_idempotent_reprocessing_preserves_records_and_updates_links")


def test_7_get_ranked_entities_and_filtering():
    """Verify GET /cases/{case_id}/possible-entities with rank ordering and filters."""
    db = SessionLocal()
    try:
        case = db.query(Case).filter(Case.case_id == "TEST-SUSPECT-CASE-1").first()

        # 1. Fetch all
        all_ranked = get_case_ranked_possible_entities(db, case)
        assert len(all_ranked) >= 3
        # Check sorted by rank ascending
        ranks = [e.rank for e in all_ranked]
        assert ranks == sorted(ranks)

        # 2. Limit filter
        limited = get_case_ranked_possible_entities(db, case, limit=2)
        assert len(limited) == 2
        assert limited[0].rank == 1
        assert limited[1].rank == 2

        # 3. Entity type filter
        emails_only = get_case_ranked_possible_entities(db, case, entity_type="EMAIL")
        for ent in emails_only:
            assert ent.entity_type == "EMAIL"
    finally:
        db.close()
    print("PASS: test_7_get_ranked_entities_and_filtering")


def test_8_summary_overview_metrics():
    """Verify GET /cases/{case_id}/possible-entities/summary returns dynamic metrics."""
    db = SessionLocal()
    try:
        case = db.query(Case).filter(Case.case_id == "TEST-SUSPECT-CASE-1").first()
        summary = get_case_possible_entities_summary(db, case)

        assert summary.case_id == case.case_id
        assert summary.total_suspects_entities >= 3
        assert summary.email_addresses >= 1
        assert summary.ip_addresses >= 1
        assert summary.wallet_addresses >= 1
        assert summary.highest_score >= summary.lowest_score
        assert summary.average_score > 0.0
        assert len(summary.top_entities) <= 5
        assert "EMAIL" in summary.entity_type_distribution
    finally:
        db.close()
    print("PASS: test_8_summary_overview_metrics")


def test_9_single_entity_detail_retrieval_and_404():
    """Verify GET /cases/{case_id}/possible-entities/{entity_id} returns full detail with linked evidence."""
    db = SessionLocal()
    try:
        case = db.query(Case).filter(Case.case_id == "TEST-SUSPECT-CASE-1").first()
        first_ent = db.query(PossibleEntity).filter(PossibleEntity.case_id == case.id).first()

        # Retrieve by ID
        detail_by_id = get_possible_entity_detail(db, case, first_ent.id)
        assert detail_by_id.id == first_ent.id
        assert detail_by_id.suspect_id == first_ent.suspect_id
        assert len(detail_by_id.linked_evidence) == first_ent.linked_evidence_count

        # Check linked evidence metadata
        for ev_item in detail_by_id.linked_evidence:
            assert ev_item.evidence_id.startswith("EV-")
            assert ev_item.file_name is not None
            assert ev_item.file_type is not None

        # Retrieve by suspect_id
        detail_by_code = get_possible_entity_detail(db, case, first_ent.suspect_id)
        assert detail_by_code.id == first_ent.id

        # Non-existent entity must 404
        try:
            get_possible_entity_detail(db, case, "NON_EXISTENT_ENTITY_XYZ")
            assert False, "Must raise 404"
        except HTTPException as e:
            assert e.status_code == 404
    finally:
        db.close()
    print("PASS: test_9_single_entity_detail_retrieval_and_404")


def test_10_cross_case_isolation():
    """Verify entities belonging to Case A are strictly isolated from Case B."""
    db = SessionLocal()
    try:
        expert = db.query(User).filter(User.role_id == 3).first()

        case_a = db.query(Case).filter(Case.case_id == "TEST-SUSPECT-CASE-1").first()
        case_b = db.query(Case).filter(Case.case_id == "TEST-SUSPECT-CASE-2").first()
        if not case_b:
            case_b = Case(
                case_id="TEST-SUSPECT-CASE-2",
                title="Secondary Investigation",
                cyber_expert_id=expert.id,
                status="Open",
                priority="Low"
            )
            db.add(case_b)
            db.commit()

        # Entities in Case A must NOT appear in Case B
        ranked_b = get_case_ranked_possible_entities(db, case_b)
        assert len(ranked_b) == 0

        # Querying Case A's entity using Case B context must return 404
        ent_a = db.query(PossibleEntity).filter(PossibleEntity.case_id == case_a.id).first()
        if ent_a:
            try:
                get_possible_entity_detail(db, case_b, ent_a.id)
                assert False, "Cross-case access must raise 404"
            except HTTPException as e:
                assert e.status_code == 404
    finally:
        db.close()
    print("PASS: test_10_cross_case_isolation")


def test_11_no_frontend_files_touched():
    """Verify git status shows ZERO modifications or additions inside frontend/."""
    out = subprocess.check_output(["git", "status", "--porcelain", "frontend/"]).decode("utf-8")
    assert out.strip() == "", f"Frontend directory must be untouched! Found changes:\n{out}"
    print("PASS: test_11_no_frontend_files_touched")


if __name__ == "__main__":
    print("\n========================================================")
    print("RUNNING SUSPECT / ENTITY RANKING INTEGRATION TESTS")
    print("========================================================")
    test_1_routes_registered_and_endpoints_correct()
    test_2_cyber_expert_authorization_and_case_scoping()
    test_3_safe_actor_extraction_and_transaction_isolation()
    test_4_suspect_ranking_scoring_and_tie_breaking()
    test_5_full_case_processing_and_relational_link_storage()
    test_6_idempotent_reprocessing_preserves_records_and_updates_links()
    test_7_get_ranked_entities_and_filtering()
    test_8_summary_overview_metrics()
    test_9_single_entity_detail_retrieval_and_404()
    test_10_cross_case_isolation()
    test_11_no_frontend_files_touched()
    print("\n========================================================")
    print("ALL 11 SUSPECT RANKING INTEGRATION TESTS PASSED!")
    print("========================================================")
