"""
End-to-End Integration tests for Relationship Analysis & Graph endpoints:
- JWT & Role Authorization (Cyber Expert role_id == 3)
- Assigned-Case Authorization
- Cross-Case Boundary Isolation
- Truthful Empty Graph Handling
- Dynamic Real Nodes & Edges (Evidence, Suspects, Devices)
- Bitwise Exact Duplicate Detection via verified SHA-256
- Custom Links (Device & Suspect assertions)
- Summary Cards Derivation
- CBIR Query with Forensic Disclaimer
"""
import sys
from pathlib import Path
from datetime import datetime, timezone
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from database.database import Base
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell

from schemas.relationship_graph import CreateLinkRequest
from services.relationship_graph_service import RelationshipGraphService
from routes.relationship_routes import (
    get_relationship_graph,
    get_relationship_summary,
    get_duplicate_pairs,
    create_evidence_link,
    list_evidence_links,
    delete_evidence_link,
    run_cbir_query
)
from fastapi import HTTPException


def setup_in_memory_db():
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
            PossibleEntity.__table__,
            PossibleEntityEvidenceLink.__table__,
            EvidenceLink.__table__
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Seed Users
    expert_user = User(
        id=301,
        full_name="Analyst Trisha",
        username="trisha_expert",
        email="trisha@cyber.gov.in",
        phone_number="9876543210",
        password="hashed_password_123",
        role_id=3,  # Cyber Expert
        cyber_cell_id=1,
        is_active=True
    )
    other_expert = User(
        id=302,
        full_name="Analyst Bob",
        username="bob_expert",
        email="bob@cyber.gov.in",
        phone_number="9876543211",
        password="hashed_password_123",
        role_id=3,
        cyber_cell_id=1,
        is_active=True
    )
    investigator_user = User(
        id=303,
        full_name="Officer Gunjan",
        username="gunjan_investigator",
        email="gunjan@police.gov.in",
        phone_number="9876543212",
        password="hashed_password_123",
        role_id=2,  # Assigned Investigator
        cyber_cell_id=1,
        is_active=True
    )
    unassigned_inv = User(
        id=304,
        full_name="Officer Unassigned",
        username="unassigned_inv",
        email="unassigned@police.gov.in",
        phone_number="9876543213",
        password="hashed_password_123",
        role_id=2,  # Unassigned Investigator
        cyber_cell_id=1,
        is_active=True
    )
    db.add_all([expert_user, other_expert, investigator_user, unassigned_inv])
    db.commit()

    # Seed Cases
    case_a = Case(
        id=101,
        case_id="CASE-REL-01",
        title="Financial Fraud Alpha",
        priority="High",
        status="Under Review",
        cyber_expert_id=301,
        investigator_id=303
    )
    case_b = Case(
        id=102,
        case_id="CASE-REL-02",
        title="Ransomware Beta",
        priority="Medium",
        status="Open",
        cyber_expert_id=302,  # Assigned to other expert
        investigator_id=303
    )
    db.add_all([case_a, case_b])
    db.commit()

    return db, expert_user, other_expert, investigator_user, case_a, case_b


def test_authorization_controls():
    """Verify role authorization and case scoping."""
    print("Testing Authorization Controls...")
    db, expert_user, other_expert, investigator_user, case_a, case_b = setup_in_memory_db()
    unassigned_inv = db.query(User).filter(User.id == 304).first()

    # 1. Unassigned investigator rejected from reading case
    try:
        get_relationship_graph("CASE-REL-01", db=db, current_user=unassigned_inv)
        assert False, "Unassigned investigator should have been forbidden"
    except HTTPException as e:
        assert e.status_code == 403

    # 2. Assigned investigator CAN read relationship graph
    inv_graph = get_relationship_graph("CASE-REL-01", db=db, current_user=investigator_user)
    assert inv_graph.status == "Success"

    # 3. Investigator CANNOT create relationship links (mutation forbidden)
    try:
        create_evidence_link("CASE-REL-01", CreateLinkRequest(evidence_id="1", suspect_name="Test Suspect"), db=db, current_user=investigator_user)
        assert False, "Investigator should be forbidden from creating links"
    except HTTPException as e:
        assert e.status_code == 403
        assert "Only Cyber Experts" in e.detail

    # 4. Expert accessing case assigned to another expert rejected
    try:
        get_relationship_graph("CASE-REL-02", db=db, current_user=expert_user)
        assert False, "Unassigned expert should have been forbidden"
    except HTTPException as e:
        assert e.status_code == 403
        assert "not assigned as the Cyber Expert" in e.detail

    # 5. Non-existent case rejected with 404
    try:
        get_relationship_graph("CASE-NON-EXISTENT", db=db, current_user=expert_user)
        assert False, "Non-existent case should return 404"
    except HTTPException as e:
        assert e.status_code == 404

    print("  [PASS] Role checks and assigned-case access restrictions strictly enforced.")


def test_empty_case_truthful_graph():
    """Verify that a case with no evidence returns a truthful empty graph with 0 mock nodes."""
    print("Testing Truthful Empty Graph...")
    db, expert_user, _, _, case_a, _ = setup_in_memory_db()

    resp = get_relationship_graph("CASE-REL-01", db=db, current_user=expert_user)
    assert resp.status == "Success"
    assert resp.case_id == "CASE-REL-01"
    assert len(resp.nodes) == 0
    assert len(resp.edges) == 0
    assert resp.summary.total_nodes == 0
    assert resp.summary.total_edges == 0
    assert resp.summary.evidence_count == 0
    assert resp.summary.suspect_count == 0
    assert resp.summary.device_count == 0
    assert resp.summary.duplicate_pairs_count == 0
    print("  [PASS] Empty case returns 0 nodes, 0 edges, and zero fabricated entities.")


def test_dynamic_graph_with_evidence_and_suspects():
    """Verify dynamic node and edge generation for real evidence and suspect records."""
    print("Testing Dynamic Graph with Evidence and Suspects...")
    db, expert_user, _, _, case_a, _ = setup_in_memory_db()

    # Create real evidence
    ev1 = Evidence(
        id=501,
        evidence_id="EV-101-01",
        case_id=case_a.id,
        file_name="financial_ledger.xlsx",
        file_type="SPREADSHEET",
        file_size=1048576,
        file_path="uploads/case_101/ledger.xlsx"
    )
    ev2 = Evidence(
        id=502,
        evidence_id="EV-101-02",
        case_id=case_a.id,
        file_name="suspicious_mail.eml",
        file_type="TEXT",
        file_size=2048,
        file_path="uploads/case_101/mail.eml"
    )
    db.add_all([ev1, ev2])
    db.commit()

    # Create real suspect entity extracted from evidence
    pe1 = PossibleEntity(
        id=701,
        case_id=case_a.id,
        suspect_id="SUSPECT-E45A89",
        suspect_name="fraudster@shellcorp.com",
        entity_type="EMAIL",
        rank=1,
        total_epra_score=88.5,
        linked_evidence_count=1,
        confidence_score=0.92
    )
    db.add(pe1)
    db.commit()

    # Link suspect to ev2
    link1 = PossibleEntityEvidenceLink(
        id=901,
        entity_id=pe1.id,
        evidence_id=ev2.id
    )
    db.add(link1)
    db.commit()

    resp = get_relationship_graph("CASE-REL-01", db=db, current_user=expert_user)
    assert resp.summary.total_nodes == 3  # 2 Evidence + 1 Suspect
    assert resp.summary.evidence_count == 2
    assert resp.summary.suspect_count == 1
    assert resp.summary.total_edges == 1

    node_ids = {n.id for n in resp.nodes}
    assert "ev_501" in node_ids
    assert "ev_502" in node_ids
    assert "suspect_701" in node_ids

    edge = resp.edges[0]
    assert edge.source == "ev_502"
    assert edge.target == "suspect_701"
    assert edge.relationship_type == "EVIDENCE_SUSPECT_LINK"
    assert "Associated EMAIL" in edge.label
    print("  [PASS] Evidence and Suspect nodes dynamically linked via genuine relationship.")


def test_exact_duplicate_sha256_detection():
    """Verify that bitwise duplicates sharing verified SHA-256 produce EXACT_DUPLICATE edges."""
    print("Testing Exact Duplicate SHA-256 Detection...")
    db, expert_user, _, _, case_a, _ = setup_in_memory_db()

    # Create 2 evidence files with identical verified hash
    ev1 = Evidence(
        id=601,
        evidence_id="EV-DUP-01",
        case_id=case_a.id,
        file_name="original_photo.jpg",
        file_type="IMAGE",
        file_size=54321,
        file_path="uploads/photo1.jpg"
    )
    ev2 = Evidence(
        id=602,
        evidence_id="EV-DUP-02",
        case_id=case_a.id,
        file_name="copy_photo.jpg",
        file_type="IMAGE",
        file_size=54321,
        file_path="uploads/photo2.jpg"
    )
    db.add_all([ev1, ev2])
    db.commit()

    identical_sha = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    h1 = EvidenceHash(
        id=801,
        evidence_id=ev1.id,
        file_name=ev1.file_name,
        sha256_hash=identical_sha,
        current_hash=identical_sha,
        hash_match=True,
        integrity_status="Verified"
    )
    h2 = EvidenceHash(
        id=802,
        evidence_id=ev2.id,
        file_name=ev2.file_name,
        sha256_hash=identical_sha,
        current_hash=identical_sha,
        hash_match=True,
        integrity_status="Verified"
    )
    db.add_all([h1, h2])
    db.commit()

    resp = get_relationship_graph("CASE-REL-01", db=db, current_user=expert_user)
    assert resp.summary.duplicate_pairs_count == 1
    assert len(resp.edges) == 1

    edge = resp.edges[0]
    assert edge.relationship_type in ("EXACT_DUPLICATE", "EXACT_FILE_DUPLICATE")
    assert edge.similarity == 1.0
    assert edge.label == "Exact Duplicate (SHA-256 Match)"

    # Test duplicate endpoint directly
    dup_pairs = get_duplicate_pairs("CASE-REL-01", db=db, current_user=expert_user)
    assert len(dup_pairs) == 1
    assert dup_pairs[0].evidence_id_1 == "EV-DUP-01"
    assert dup_pairs[0].evidence_id_2 == "EV-DUP-02"
    assert dup_pairs[0].sha256_hash == identical_sha
    print("  [PASS] Exact duplicates identified strictly from matching verified SHA-256 hashes.")


def test_custom_evidence_links_and_device_nodes():
    """Verify adding, listing, and deleting custom evidence links (adapting Trisha's evidence_linker)."""
    print("Testing Custom Evidence Links & Device Nodes...")
    db, expert_user, _, _, case_a, _ = setup_in_memory_db()

    ev = Evidence(
        id=701,
        evidence_id="EV-PHONE-01",
        case_id=case_a.id,
        file_name="chat_dump.txt",
        file_type="TEXT",
        file_size=8192,
        file_path="uploads/chat.txt"
    )
    db.add(ev)
    db.commit()

    # 1. Create link with device
    req = CreateLinkRequest(
        evidence_id="EV-PHONE-01",
        device_name="Samsung Galaxy S22",
        suspect_name="Target A",
        relationship_type="EXTRACTED_FROM_DEVICE",
        notes="Physical extraction by forensic lab"
    )
    created = create_evidence_link("CASE-REL-01", link_data=req, db=db, current_user=expert_user)
    assert created.device_name == "Samsung Galaxy S22"
    assert created.suspect_name == "Target A"
    assert created.external_evidence_id == "EV-PHONE-01"

    # 2. Check Graph reflection
    graph = get_relationship_graph("CASE-REL-01", db=db, current_user=expert_user)
    assert graph.summary.device_count == 1
    device_nodes = [n for n in graph.nodes if n.node_type == "Device"]
    assert len(device_nodes) == 1
    assert device_nodes[0].label == "Samsung Galaxy S22"

    # 3. List links
    links_list = list_evidence_links("CASE-REL-01", db=db, current_user=expert_user)
    assert len(links_list) == 1

    # 4. Delete link
    del_res = delete_evidence_link("CASE-REL-01", link_id=created.id, db=db, current_user=expert_user)
    assert del_res["status"] == "Success"

    # Check graph after deletion
    graph_after = get_relationship_graph("CASE-REL-01", db=db, current_user=expert_user)
    assert graph_after.summary.device_count == 0
    assert len(graph_after.edges) == 0
    print("  [PASS] Custom evidence links created, reflected in graph as Device nodes, and deleted cleanly.")


def test_cross_case_isolation():
    """Verify that Case A graph contains zero data from Case B."""
    print("Testing Cross-Case Boundary Isolation...")
    db, expert_user, other_expert, _, case_a, case_b = setup_in_memory_db()

    # Evidence in Case A
    ev_a = Evidence(
        id=801,
        evidence_id="EV-CASE-A-01",
        case_id=case_a.id,
        file_name="case_a_file.pdf",
        file_type="PDF",
        file_size=1000,
        file_path="case_a/file.pdf"
    )
    # Evidence in Case B
    ev_b = Evidence(
        id=802,
        evidence_id="EV-CASE-B-01",
        case_id=case_b.id,
        file_name="case_b_file.pdf",
        file_type="PDF",
        file_size=2000,
        file_path="case_b/file.pdf"
    )
    db.add_all([ev_a, ev_b])
    db.commit()

    # Fetch Case A graph as expert_user
    graph_a = get_relationship_graph("CASE-REL-01", db=db, current_user=expert_user)
    node_labels_a = [n.label for n in graph_a.nodes]
    assert "case_a_file.pdf" in node_labels_a
    assert "case_b_file.pdf" not in node_labels_a

    # Fetch Case B graph as other_expert
    graph_b = get_relationship_graph("CASE-REL-02", db=db, current_user=other_expert)
    node_labels_b = [n.label for n in graph_b.nodes]
    assert "case_b_file.pdf" in node_labels_b
    assert "case_a_file.pdf" not in node_labels_b
    print("  [PASS] Strict cross-case isolation verified; zero cross-case leakage.")


def test_cbir_query_endpoint():
    """Verify CBIR query endpoint returns case-restricted search and forensic disclaimer."""
    print("Testing CBIR Query Endpoint...")
    db, expert_user, _, _, case_a, _ = setup_in_memory_db()

    ev = Evidence(
        id=901,
        evidence_id="EV-IMG-01",
        case_id=case_a.id,
        file_name="crime_scene.jpg",
        file_type="IMAGE",
        file_size=65000,
        file_path="datasets/images/crime_scene/scene1.jpg"
    )
    db.add(ev)
    db.commit()

    cbir_res = run_cbir_query("CASE-REL-01", evidence_id="EV-IMG-01", top_k=5, db=db, current_user=expert_user)
    assert cbir_res.status == "Success"
    assert cbir_res.source_evidence == "EV-IMG-01"
    assert cbir_res.total_case_evidence == 1
    assert "Investigator verification is required" in cbir_res.forensic_notice
    print("  [PASS] CBIR query executes within case boundary with mandatory forensic disclaimer.")


if __name__ == "__main__":
    print("=" * 70)
    print("RUNNING RELATIONSHIP MODULE INTEGRATION TESTS")
    print("=" * 70)

    tests = [
        test_authorization_controls,
        test_empty_case_truthful_graph,
        test_dynamic_graph_with_evidence_and_suspects,
        test_exact_duplicate_sha256_detection,
        test_custom_evidence_links_and_device_nodes,
        test_cross_case_isolation,
        test_cbir_query_endpoint
    ]

    passed = 0
    failed = 0

    for t in tests:
        try:
            t()
            passed += 1
        except Exception as e:
            import traceback
            traceback.print_exc()
            print(f"  [FAIL] {t.__name__}: {e}")
            failed += 1

    print("=" * 70)
    print(f"RELATIONSHIP INTEGRATION TEST RESULTS: {passed} passed, {failed} failed")
    print("=" * 70)
    if failed > 0:
        sys.exit(1)
