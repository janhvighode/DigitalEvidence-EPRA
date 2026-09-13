"""
Comprehensive Test Suite for Investigator Dashboard and My Assigned Cases
Validates:
1. role_id 2 can access Investigator Dashboard
2. role_id 3 cannot impersonate Investigator Dashboard
3. role_id 1 behavior follows intended route restriction
4. only assigned cases counted
5. no cross-investigator leakage
6. total assigned cases
7. active cases
8. completed cases
9. evidence uploaded
10. pending analysis
11. new analysis results
12. attention cases
13. evidence status
14. case status distribution
15. empty Investigator
16. Investigator with zero evidence
17. My Assigned Cases pagination
18. search
19. status filter
20. priority filter
21. Cyber Expert filter
22. analysis progress
23. evidence upload existing API remains functional
24. evidence list remains functional
25. Investigator can read assigned-case EPRA
26. Investigator cannot process EPRA
27. Investigator can read assigned relationship graph
28. Investigator cannot modify relationship graph
29. Investigator can read/download assigned-case reports
30. Investigator cannot perform prohibited report mutations
31. Cyber Expert functionality remains intact
"""
import sys
from pathlib import Path
from datetime import datetime, timezone
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
from models.epra_result import EPRAResult
from models.report_record import ReportRecord
from models.notification import Notification
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink

from schemas.relationship_graph import CreateLinkRequest
from schemas.technical_report import ReportRequest

from routes.investigator_dashboard_routes import (
    verify_investigator,
    fetch_dashboard_stats,
    fetch_cases_requiring_attention,
    fetch_evidence_status,
    fetch_case_status_distribution,
    fetch_investigator_my_cases
)
from services.investigator_dashboard_service import (
    get_investigator_dashboard_stats,
    get_cases_requiring_attention,
    get_evidence_status,
    get_case_status_distribution,
    get_investigator_my_cases
)
from services.evidence_service import authorize_case_access, get_case_evidence_list
from services.epra_service import (
    authorize_cyber_expert_case_access,
    authorize_epra_read_case_access,
    get_case_epra_summary
)
from services.relationship_graph_service import RelationshipGraphService
from routes.technical_report_routes import (
    verify_cyber_expert_case_access,
    verify_report_read_access
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
            ReportRecord.__table__,
            Notification.__table__,
            PossibleEntity.__table__,
            PossibleEntityEvidenceLink.__table__,
            EvidenceLink.__table__
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Seed Users
    # 1 = Admin, 2 = Investigator, 3 = Cyber Expert
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
        id=203, full_name="Inspector Empty", username="empty_inv", email="empty@police.gov.in",
        phone_number="9000000004", password="hash", role_id=2, cyber_cell_id=1, is_active=True
    )
    cyber_expert_1 = User(
        id=301, full_name="Analyst Rajesh", username="rajesh_ce", email="rajesh@police.gov.in",
        phone_number="9000000005", password="hash", role_id=3, cyber_cell_id=1, is_active=True
    )
    cyber_expert_2 = User(
        id=302, full_name="Analyst Trisha", username="trisha_ce", email="trisha@police.gov.in",
        phone_number="9000000006", password="hash", role_id=3, cyber_cell_id=1, is_active=True
    )

    db.add_all([admin, investigator_1, investigator_2, empty_investigator, cyber_expert_1, cyber_expert_2])
    db.commit()

    # Seed Cases for investigator_1 (id=201):
    # Case 1: Open, High priority, has tampered evidence -> Attention case
    c1 = Case(
        id=1, case_id="CASE-2024-001", title="Bank Phishing Fraud",
        description="Investigation into unauthorized bank transfers",
        investigator_id=201, cyber_expert_id=301, priority="High", status="Open", created_by=101
    )
    # Case 2: In Progress, Critical priority, has critical EPRA result -> Attention case
    c2 = Case(
        id=2, case_id="CASE-2024-002", title="Ransomware Outbreak",
        description="Malware encrypted enterprise servers",
        investigator_id=201, cyber_expert_id=301, priority="Critical", status="In Progress", created_by=101
    )
    # Case 3: Under Review, Medium priority -> Active case
    c3 = Case(
        id=3, case_id="CASE-2024-003", title="Data Exfiltration Incident",
        description="Confidential blueprints leaked via USB",
        investigator_id=201, cyber_expert_id=302, priority="Medium", status="Under Review", created_by=101
    )
    # Case 4: Closed, Low priority -> Completed case
    c4 = Case(
        id=4, case_id="CASE-2024-004", title="Defamatory Social Post",
        description="Impersonation on Twitter resolved",
        investigator_id=201, cyber_expert_id=301, priority="Low", status="Closed", created_by=101
    )
    # Case 5: Zero-evidence case for investigator_1
    c5 = Case(
        id=5, case_id="CASE-2024-005", title="Freshly Assigned Stalker Case",
        description="Pending evidence intake",
        investigator_id=201, cyber_expert_id=302, priority="Low", status="Open", created_by=101
    )

    # Seed Case for investigator_2 (id=202) -> Cross-case isolation check
    c6 = Case(
        id=6, case_id="CASE-2024-006", title="Crypto Scam Operation",
        description="Investigator Priya case",
        investigator_id=202, cyber_expert_id=302, priority="High", status="In Progress", created_by=101
    )

    db.add_all([c1, c2, c3, c4, c5, c6])
    db.commit()

    # Seed Evidence for Case 1 (2 items)
    ev1 = Evidence(id=1, evidence_id="EV-001", case_id=1, file_name="phish.eml", file_type="message/rfc822", file_size=1024, file_path="/storage/1.eml")
    ev2 = Evidence(id=2, evidence_id="EV-002", case_id=1, file_name="server_log.txt", file_type="text/plain", file_size=2048, file_path="/storage/2.txt")
    # Evidence 1 is tampered!
    h1 = EvidenceHash(id=1, evidence_id=1, file_name="phish.eml", sha256_hash="hash1", current_hash="hash1_tampered", original_hash="hash1", hash_match=False, tampered=True, integrity_status="TAMPERED")
    # Evidence 2 is verified
    h2 = EvidenceHash(id=2, evidence_id=2, file_name="server_log.txt", sha256_hash="hash2", current_hash="hash2", original_hash="hash2", hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime.now())
    # Evidence 1 has completed EPRA
    epra1 = EPRAResult(id=1, case_id=1, evidence_id=1, priority="High", analysis_status="COMPLETE", epra_score=0.85)

    # Seed Evidence for Case 2 (2 items)
    ev3 = Evidence(id=3, evidence_id="EV-003", case_id=2, file_name="ransom_note.txt", file_type="text/plain", file_size=512, file_path="/storage/3.txt")
    ev4 = Evidence(id=4, evidence_id="EV-004", case_id=2, file_name="memory_dump.raw", file_type="application/octet-stream", file_size=1048576, file_path="/storage/4.raw")
    h3 = EvidenceHash(id=3, evidence_id=3, file_name="ransom_note.txt", sha256_hash="hash3", current_hash="hash3", original_hash="hash3", hash_match=True, tampered=False, integrity_status="Verified", verified_at=datetime.now())
    h4 = EvidenceHash(id=4, evidence_id=4, file_name="memory_dump.raw", sha256_hash="hash4", current_hash="hash4", original_hash=None, integrity_status="Unknown")
    # Evidence 3 has Critical EPRA priority
    epra3 = EPRAResult(id=2, case_id=2, evidence_id=3, priority="Critical", analysis_status="COMPLETE", epra_score=0.98)
    # Evidence 4 has PARTIAL EPRA status
    epra4 = EPRAResult(id=3, case_id=2, evidence_id=4, priority="Medium", analysis_status="PARTIAL / PENDING INPUTS", epra_score=0.55)

    # Seed Evidence for Case 3 (1 item, no EPRAResult -> pending analysis)
    ev5 = Evidence(id=5, evidence_id="EV-005", case_id=3, file_name="usb_dump.dd", file_type="application/octet-stream", file_size=4096, file_path="/storage/5.dd")
    h5 = EvidenceHash(id=5, evidence_id=5, file_name="usb_dump.dd", sha256_hash="hash5", current_hash="hash5", integrity_status="Verified", hash_match=True, verified_at=datetime.now())

    # Seed Evidence for Case 4 (1 item, Closed case, completed EPRA)
    ev6 = Evidence(id=6, evidence_id="EV-006", case_id=4, file_name="tweet_screenshot.png", file_type="image/png", file_size=512000, file_path="/storage/6.png")
    h6 = EvidenceHash(id=6, evidence_id=6, file_name="tweet_screenshot.png", sha256_hash="hash6", current_hash="hash6", hash_match=True, integrity_status="Verified", verified_at=datetime.now())
    epra6 = EPRAResult(id=4, case_id=4, evidence_id=6, priority="Low", analysis_status="COMPLETE", epra_score=0.20)

    # Seed Evidence for Case 6 (Investigator Priya's case -> should never be counted for Vikram)
    ev7 = Evidence(id=7, evidence_id="EV-007", case_id=6, file_name="wallet_keys.json", file_type="application/json", file_size=1024, file_path="/storage/7.json")

    # Seed Report for Case 1
    rep1 = ReportRecord(
        id="REP-001", case_id="1", case_title="Bank Phishing Fraud",
        investigator_name="Inspector Vikram", generated_by_id="301", generated_by_role="Cyber Expert",
        report_type="Comprehensive Forensic Report", file_format="PDF", file_size_bytes=10000,
        file_path="/storage/rep1.pdf", file_name="rep1.pdf", is_draft=False
    )

    db.add_all([ev1, ev2, ev3, ev4, ev5, ev6, ev7, h1, h2, h3, h4, h5, h6, epra1, epra3, epra4, epra6, rep1])
    db.commit()

    return db, {
        "admin": admin,
        "investigator_1": investigator_1,
        "investigator_2": investigator_2,
        "empty_investigator": empty_investigator,
        "cyber_expert_1": cyber_expert_1,
        "cyber_expert_2": cyber_expert_2,
        "c1": c1, "c2": c2, "c3": c3, "c4": c4, "c5": c5, "c6": c6
    }


def run_all_tests():
    db, ctx = setup_test_db()
    inv1 = ctx["investigator_1"]
    inv2 = ctx["investigator_2"]
    empty_inv = ctx["empty_investigator"]
    ce1 = ctx["cyber_expert_1"]
    admin = ctx["admin"]

    print("======================================================================")
    print("RUNNING INVESTIGATOR DASHBOARD & MY CASES INTEGRATION TESTS")
    print("======================================================================")

    # Test 1: role_id 2 can access Investigator Dashboard
    res = verify_investigator(inv1)
    assert res.id == inv1.id
    print("  [PASS] 1. role_id 2 can access Investigator Dashboard")

    # Test 2: role_id 3 cannot impersonate Investigator Dashboard
    try:
        verify_investigator(ce1)
        assert False, "Cyber Expert should be rejected from investigator endpoints"
    except HTTPException as e:
        assert e.status_code == 403
        assert "Investigator access required" in e.detail
    print("  [PASS] 2. role_id 3 cannot access Investigator Dashboard")

    # Test 3: role_id 1 admin cannot access Investigator Dashboard
    try:
        verify_investigator(admin)
        assert False, "Admin should be rejected from investigator endpoints"
    except HTTPException as e:
        assert e.status_code == 403
        assert "Investigator access required" in e.detail
    print("  [PASS] 3. role_id 1 behavior follows intended route restriction (403)")

    # Test 4 & 6: Total Assigned Cases for Investigator 1
    stats = get_investigator_dashboard_stats(db, inv1)
    assert stats.total_assigned_cases == 5, f"Expected 5 assigned cases, got {stats.total_assigned_cases}"
    print("  [PASS] 4 & 6. only assigned cases counted & total assigned cases == 5")

    # Test 5: No cross-investigator leakage
    stats2 = get_investigator_dashboard_stats(db, inv2)
    assert stats2.total_assigned_cases == 1
    assert stats2.evidence_uploaded == 1
    print("  [PASS] 5. no cross-investigator leakage (Investigator 2 sees only their 1 case)")

    # Test 7: Active Cases (Open, In Progress, Under Review)
    # c1 (Open), c2 (In Progress), c3 (Under Review), c5 (Open) -> 4 active
    assert stats.active_cases == 4, f"Expected 4 active cases, got {stats.active_cases}"
    print("  [PASS] 7. active cases (Open + In Progress + Under Review) == 4")

    # Test 8: Completed Cases (Closed)
    # c4 (Closed) -> 1 completed
    assert stats.completed_cases == 1, f"Expected 1 completed case, got {stats.completed_cases}"
    print("  [PASS] 8. completed cases (Closed) == 1")

    # Test 9: Evidence Uploaded
    # c1 has 2, c2 has 2, c3 has 1, c4 has 1, c5 has 0 -> Total = 6
    assert stats.evidence_uploaded == 6, f"Expected 6 evidence uploaded, got {stats.evidence_uploaded}"
    print("  [PASS] 9. evidence uploaded across assigned cases == 6")

    # Test 10: Evidence Pending Analysis
    # Analyzed with COMPLETE: epra1 (ev1), epra3 (ev3), epra6 (ev6) = 3
    # Total evidence = 6 -> Pending = 6 - 3 = 3
    assert stats.evidence_pending_analysis == 3, f"Expected 3 pending analysis, got {stats.evidence_pending_analysis}"
    print("  [PASS] 10. evidence pending analysis derived truthfully == 3")

    # Test 11: New Analysis Results
    # In active assigned cases (c1, c2, c3, c5), completed EPRA results: epra1 (ev1), epra3 (ev3) = 2
    assert stats.new_analysis_results == 2, f"Expected 2 new analysis results, got {stats.new_analysis_results}"
    print("  [PASS] 11. new analysis results deterministic rule == 2")

    # Test 12: Cases Requiring Attention
    # c1: tampered evidence (ev1) + open high priority -> Attention
    # c2: critical EPRA evidence (ev3) -> Attention
    # c5: open low priority -> Not attention
    # c3: under review medium -> Not attention
    # c4: closed low -> Not attention
    # Total = 2 cases requiring attention
    attention_cases = get_cases_requiring_attention(db, inv1)
    assert len(attention_cases) == 2, f"Expected 2 attention cases, got {len(attention_cases)}"
    attention_ids = {a.case_id for a in attention_cases}
    assert attention_ids == {"CASE-2024-001", "CASE-2024-002"}
    # Deduplication check: Case 1 has both tampered evidence AND high priority open
    c1_att = next(a for a in attention_cases if a.case_id == "CASE-2024-001")
    assert "integrity compromised" in c1_att.reason
    assert "High priority case pending" in c1_att.reason
    print("  [PASS] 12. attention cases deduplication and genuine conditions verified")

    # Test 13: Evidence Status Breakdown
    ev_status = get_evidence_status(db, inv1)
    assert ev_status.total_evidence == 6
    assert ev_status.analyzed == 3
    assert ev_status.pending_analysis == 3
    assert ev_status.integrity_verified == 4  # ev2, ev3, ev5, ev6
    assert ev_status.integrity_issue == 1     # ev1 tampered
    assert ev_status.pending_verification == 1 # ev4 Unknown
    print("  [PASS] 13. evidence status breakdown (analyzed vs pending, verified vs tampered vs pending) verified")

    # Test 14: Case Status Distribution
    dist = get_case_status_distribution(db, inv1)
    assert dist.open == 2        # c1, c5
    assert dist.in_progress == 1 # c2
    assert dist.under_review == 1# c3
    assert dist.closed == 1      # c4
    assert dist.total == 5
    print("  [PASS] 14. case status distribution (Open:2, In Progress:1, Under Review:1, Closed:1)")

    # Test 15: Empty Investigator
    empty_stats = get_investigator_dashboard_stats(db, empty_inv)
    assert empty_stats.total_assigned_cases == 0
    assert empty_stats.active_cases == 0
    assert empty_stats.evidence_uploaded == 0
    assert empty_stats.evidence_pending_analysis == 0
    assert empty_stats.new_analysis_results == 0
    assert empty_stats.cases_requiring_attention == 0
    assert empty_stats.completed_cases == 0
    empty_attention = get_cases_requiring_attention(db, empty_inv)
    assert len(empty_attention) == 0
    print("  [PASS] 15. empty investigator returns all 0s cleanly")

    # Test 16: Investigator with zero evidence (c5 has 0 evidence)
    c5_item = get_investigator_my_cases(db, inv1, search="CASE-2024-005").cases[0]
    assert c5_item.evidence_count == 0
    assert c5_item.analyzed_evidence_count == 0
    assert c5_item.pending_analysis_count == 0
    assert c5_item.analysis_progress == 0.0
    print("  [PASS] 16. investigator zero evidence handled safely (progress = 0.0)")

    # Test 17: My Assigned Cases Pagination
    page1 = get_investigator_my_cases(db, inv1, page=1, limit=2)
    assert page1.total == 5
    assert len(page1.cases) == 2
    assert page1.page == 1
    page2 = get_investigator_my_cases(db, inv1, page=2, limit=2)
    assert len(page2.cases) == 2
    assert page2.page == 2
    print("  [PASS] 17. my assigned cases pagination works correctly")

    # Test 18: Search filter (case_id, title, description)
    res_search = get_investigator_my_cases(db, inv1, search="Ransomware")
    assert res_search.total == 1
    assert res_search.cases[0].case_id == "CASE-2024-002"
    print("  [PASS] 18. search filter across title/case_id/description")

    # Test 19: Status filter
    res_status = get_investigator_my_cases(db, inv1, status="Closed")
    assert res_status.total == 1
    assert res_status.cases[0].case_id == "CASE-2024-004"
    print("  [PASS] 19. status filter works correctly")

    # Test 20: Priority filter
    res_prio = get_investigator_my_cases(db, inv1, priority="Critical")
    assert res_prio.total == 1
    assert res_prio.cases[0].case_id == "CASE-2024-002"
    print("  [PASS] 20. priority filter works correctly")

    # Test 21: Cyber Expert filter
    res_ce = get_investigator_my_cases(db, inv1, cyber_expert_id=302)
    assert res_ce.total == 2  # c3 and c5 assigned to 302
    for c in res_ce.cases:
        assert c.assigned_cyber_expert == "Analyst Trisha"
    print("  [PASS] 21. cyber expert filter works correctly")

    # Test 22: Analysis Progress calculation
    # c2 has 2 total evidence, 1 analyzed (ev3 is COMPLETE, ev4 is PARTIAL) -> 50.0%
    c2_item = get_investigator_my_cases(db, inv1, search="CASE-2024-002").cases[0]
    assert c2_item.evidence_count == 2
    assert c2_item.analyzed_evidence_count == 1
    assert c2_item.analysis_progress == 50.0
    print("  [PASS] 22. analysis progress calculation == 50.0%")

    # Test 23: Evidence Upload existing API remains functional for Investigator
    # authorize_case_access allows role_id == 2 when Case.investigator_id == current_user.id
    c1_access = authorize_case_access(db, "CASE-2024-001", inv1)
    assert c1_access.id == 1
    print("  [PASS] 23. evidence upload access permitted for assigned investigator")

    # Test 24: Evidence List remains functional for Investigator
    ev_list = get_case_evidence_list(db, c1_access)
    assert len(ev_list) == 2
    print("  [PASS] 24. evidence list functional for assigned investigator")

    # Test 25: Investigator can read assigned-case EPRA
    epra_case = authorize_epra_read_case_access(db, "CASE-2024-001", inv1)
    assert epra_case.id == 1
    summary = get_case_epra_summary(db, epra_case)
    assert summary["total_evidence"] == 2
    print("  [PASS] 25. investigator can read assigned-case EPRA summary")

    # Test 26: Investigator cannot process EPRA
    try:
        authorize_cyber_expert_case_access(db, "CASE-2024-001", inv1)
        assert False, "Investigator must NOT process EPRA"
    except HTTPException as e:
        assert e.status_code == 403
        assert "Cyber Expert access required" in e.detail
    print("  [PASS] 26. investigator cannot process EPRA (403 Forbidden)")

    # Test 27: Investigator can read assigned relationship graph
    graph = RelationshipGraphService.get_relationship_graph(db, "CASE-2024-001", inv1)
    assert graph.status == "Success"
    assert graph.case_id == "CASE-2024-001"
    print("  [PASS] 27. investigator can read assigned relationship graph")

    # Test 28: Investigator cannot modify relationship graph (create/delete links)
    try:
        RelationshipGraphService.create_evidence_link(
            db, "CASE-2024-001",
            CreateLinkRequest(evidence_id="EV-001", suspect_name="John Doe", relationship_type="POSSESSES"),
            inv1
        )
        assert False, "Investigator must NOT create relationship links"
    except PermissionError as pe:
        assert "Only Cyber Experts can modify case relationship links" in str(pe)
    print("  [PASS] 28. investigator cannot modify relationship graph (PermissionError)")

    # Test 29: Investigator can read/download assigned-case reports
    rep_case = verify_report_read_access(1, inv1, db)
    assert rep_case.id == 1
    print("  [PASS] 29. investigator can view/download assigned-case reports")

    # Test 30: Investigator cannot perform prohibited report mutations
    try:
        verify_cyber_expert_case_access(1, inv1, db)
        assert False, "Investigator must NOT generate reports"
    except HTTPException as e:
        assert e.status_code == 403
        assert "Access restricted to Cyber Experts only" in e.detail
    print("  [PASS] 30. investigator cannot perform report generation/mutations (403)")

    # Test 31: Cyber Expert functionality remains intact
    ce_rep_access = verify_cyber_expert_case_access(1, ce1, db)
    assert ce_rep_access.id == 1
    ce_epra_access = authorize_cyber_expert_case_access(db, "CASE-2024-001", ce1)
    assert ce_epra_access.id == 1
    ce_graph = RelationshipGraphService.get_relationship_graph(db, "CASE-2024-001", ce1)
    assert ce_graph.status == "Success"
    print("  [PASS] 31. cyber expert functionality completely intact")

    print("======================================================================")
    print("ALL 31 INVESTIGATOR DASHBOARD INTEGRATION TESTS PASSED!")
    print("======================================================================")


if __name__ == "__main__":
    run_all_tests()
