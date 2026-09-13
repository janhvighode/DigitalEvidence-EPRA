import os
import sys
import unittest
from datetime import datetime, timezone, timedelta
from pathlib import Path
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
from models.case_timeline import CaseTimeline
from models.evidence_record import EvidenceRecord
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.current_custody import CurrentCustodyInfo
from models.report_record import ReportRecord
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.evidence_link import EvidenceLink

from routes.investigator_dashboard_routes import (
    fetch_case_activity_summary,
    fetch_case_activity_timeline,
    fetch_case_activity_recent,
    fetch_case_activity_detail
)
from services.investigator_dashboard_service import (
    get_investigator_case_activity_summary,
    get_investigator_case_activity_timeline,
    get_investigator_case_activity_detail
)


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
            CaseTimeline.__table__,
            EvidenceRecord.__table__,
            CustodyLog.__table__,
            ActivityLog.__table__,
            CurrentCustodyInfo.__table__,
            ReportRecord.__table__,
            EPRAResult.__table__,
            CBIRResult.__table__,
            EvidenceLink.__table__
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Users
    inv_1 = User(
        id=201, full_name="Inspector Vikram", username="vikram_inv",
        email="vikram@police.gov.in", phone_number="9000000001",
        password="hash", role_id=2, cyber_cell_id=1, is_active=True
    )
    inv_2 = User(
        id=202, full_name="Inspector Priya", username="priya_inv",
        email="priya@police.gov.in", phone_number="9000000002",
        password="hash", role_id=2, cyber_cell_id=1, is_active=True
    )
    exp_1 = User(
        id=301, full_name="Analyst Rajesh", username="rajesh_exp",
        email="rajesh@police.gov.in", phone_number="9000000003",
        password="hash", role_id=3, cyber_cell_id=1, is_active=True
    )
    adm_1 = User(
        id=101, full_name="Admin Alice", username="alice_adm",
        email="alice@police.gov.in", phone_number="9000000004",
        password="hash", role_id=1, cyber_cell_id=1, is_active=True
    )
    db.add_all([inv_1, inv_2, exp_1, adm_1])
    db.commit()

    # Base timestamps
    t0 = datetime(2026, 9, 1, 10, 0, 0)
    t1 = datetime(2026, 9, 2, 11, 0, 0)
    t2 = datetime(2026, 9, 3, 12, 0, 0)
    t3 = datetime(2026, 9, 4, 14, 0, 0)
    t4 = datetime(2026, 9, 5, 15, 0, 0)
    t5 = datetime(2026, 9, 6, 16, 0, 0)

    # Cases
    case_active = Case(
        id=1,
        case_id="CASE-2024-001",
        title="Active Fraud Case",
        description="Comprehensive cyber fraud investigation",
        priority="High",
        status="In Progress",
        investigator_id=201,
        cyber_expert_id=301,
        created_at=t0
    )
    case_empty = Case(
        id=2,
        case_id="CASE-2024-002",
        title="Empty Case",
        description="No activities logged yet",
        priority="Low",
        status="Open",
        investigator_id=201,
        cyber_expert_id=None,
        created_at=t0
    )
    case_other = Case(
        id=3,
        case_id="CASE-2024-003",
        title="Other Officer Case",
        description="Assigned to Inspector Priya",
        priority="Medium",
        status="Open",
        investigator_id=202,
        cyber_expert_id=None,
        created_at=t0
    )
    db.add_all([case_active, case_empty, case_other])
    db.commit()

    # Evidence for Case 1
    ev1 = Evidence(
        id=10,
        case_id=1,
        evidence_id="EV-1001",
        file_name="phishing_email.eml",
        file_path="uploads/cases/1/phishing_email.eml",
        file_type="Email",
        file_size=15420,
        status="Active",
        created_at=t1
    )
    ev2 = Evidence(
        id=11,
        case_id=1,
        evidence_id="EV-1002",
        file_name="suspect_selfie.jpg",
        file_path="uploads/cases/1/suspect_selfie.jpg",
        file_type="IMAGE",
        file_size=204800,
        status="Active",
        created_at=t2
    )
    db.add_all([ev1, ev2])
    db.commit()

    # EvidenceHash for ev1
    h1 = EvidenceHash(
        id=1,
        evidence_id=10,
        file_name="phishing_email.eml",
        sha256_hash="aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888",
        current_hash="aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa7777bbbb8888",
        hash_match=True,
        tampered=False,
        integrity_status="MATCH",
        verified_at=t1,
        verified_by=201
    )
    db.add(h1)

    # CaseTimeline milestone
    ct1 = CaseTimeline(
        id=1,
        case_id=1,
        event="Case assigned to Inspector Vikram",
        performed_by=101,
        performed_by_role="Administrator",
        created_at=t0 + timedelta(minutes=30)
    )
    db.add(ct1)

    # CustodyLog and ActivityLog sharing event_reference (Deduplication test!)
    c_log1 = CustodyLog(
        id=1,
        case_id="CASE-2024-001",
        evidence_id="EV-1001",
        event_reference="EVT-UPLOAD-REF-01",
        event_type="UPLOAD",
        title="Evidence Uploaded: EV-1001",
        investigator_id="201",
        investigator_name="Inspector Vikram",
        actor_role="Investigator",
        action="EVIDENCE_UPLOADED",
        result="SUCCESS",
        remarks="Acquired from victim workstation",
        timestamp=t1
    )
    a_log1 = ActivityLog(
        id=1,
        case_id="CASE-2024-001",
        evidence_id=10,
        external_evidence_id="EV-1001",
        event_reference="EVT-UPLOAD-REF-01",
        actor_id="201",
        investigator_name="Inspector Vikram",
        action="EVIDENCE_UPLOADED",
        activity="Evidence Uploaded: EV-1001",
        outcome="SUCCESS",
        details="Acquired from victim workstation (SHA-256 computed)",
        timestamp=t1
    )
    db.add_all([c_log1, a_log1])

    # Custody transfer event
    c_log2 = CustodyLog(
        id=2,
        case_id="CASE-2024-001",
        evidence_id="EV-1001",
        event_reference="EVT-TRANS-REF-02",
        event_type="TRANSFER",
        title="Evidence Transfer Received",
        investigator_id="201",
        investigator_name="Inspector Vikram",
        actor_role="Investigator",
        action="TRANSFER_RECEIVED",
        result="SUCCESS",
        remarks="Secured in evidence vault locker B-12",
        transfer_sender="Constable Pawar",
        transfer_recipient="Inspector Vikram",
        timestamp=t2
    )
    db.add(c_log2)

    # ReportRecord
    rep1 = ReportRecord(
        id="rep-uuid-001",
        case_id="CASE-2024-001",
        case_title="Active Fraud Case",
        crime_type="Financial Fraud",
        investigator_name="Analyst Rajesh",
        generated_by_id="301",
        generated_by_role="Cyber Expert",
        report_type="Comprehensive Forensic Report",
        file_format="PDF",
        file_size_bytes=1048576,
        file_path="reports/Active_Fraud_Case_Report.pdf",
        file_name="Active_Fraud_Case_Report.pdf",
        is_draft=False,
        generated_at=t4
    )
    db.add(rep1)

    # EPRA result
    epra1 = EPRAResult(
        id=1,
        case_id=1,
        evidence_id=10,
        authenticity_risk=0.85,
        context_intelligence=0.90,
        behaviour_intelligence=0.75,
        semantic_intelligence=None,
        investigative_intelligence=0.80,
        semantic_status="PENDING",
        ipi=0.83,
        epra_score=83.5,
        priority="High",
        rank=1,
        analysis_status="COMPLETE",
        created_at=t3
    )
    db.add(epra1)

    # CBIR result
    cbir1 = CBIRResult(
        id=1,
        case_id=1,
        query_evidence_id=11,
        candidate_evidence_id=11,
        visual_similarity_score=1.0,
        semantic_score=1.0,
        classification="Exact Duplicate",
        confidence_level="High",
        verification_required=False,
        recommendation="Prioritize",
        sha256_exact_duplicate=True,
        rank=1,
        created_at=t4 + timedelta(minutes=15)
    )
    db.add(cbir1)

    # EvidenceLink
    link1 = EvidenceLink(
        id=1,
        case_id=1,
        evidence_id=10,
        suspect_name="John Doe",
        relationship_type="SUSPECT_POSSESSION",
        notes="Email retrieved from suspect USB drive",
        created_at=t5
    )
    db.add(link1)
    db.commit()

    return db, inv_1, inv_2, exp_1, adm_1


class TestInvestigatorCaseActivity(unittest.TestCase):

    def setUp(self):
        self.db, self.inv1, self.inv2, self.exp1, self.adm1 = setup_in_memory_db()

    def tearDown(self):
        self.db.close()

    # 1. Assigned Investigator can access activity summary
    def test_01_assigned_investigator_summary_access(self):
        summary = get_investigator_case_activity_summary(self.db, "CASE-2024-001", self.inv1)
        self.assertEqual(summary.case_id, "CASE-2024-001")
        self.assertGreater(summary.total_activity_count, 0)
        self.assertGreaterEqual(summary.evidence_activity_count, 1)
        self.assertGreaterEqual(summary.custody_activity_count, 1)
        self.assertGreaterEqual(summary.report_activity_count, 1)
        self.assertGreaterEqual(summary.relationship_activity_count, 1)
        self.assertIsNotNone(summary.latest_activity_at)

    # 2. Assigned Investigator can list activity
    def test_02_assigned_investigator_list_activity(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, page=1, limit=10)
        self.assertEqual(page.case_id, "CASE-2024-001")
        self.assertGreater(page.total, 0)
        self.assertGreaterEqual(len(page.activities), 1)

    # 3. Unassigned Investigator denied (403)
    def test_03_unassigned_investigator_denied(self):
        with self.assertRaises(HTTPException) as ctx:
            get_investigator_case_activity_summary(self.db, "CASE-2024-001", self.inv2)
        self.assertEqual(ctx.exception.status_code, 403)

    # 4. Missing JWT / Unauthenticated -> 401
    def test_04_missing_auth_denied(self):
        with self.assertRaises(HTTPException) as ctx:
            get_investigator_case_activity_summary(self.db, "CASE-2024-001", None)
        self.assertEqual(ctx.exception.status_code, 401)

    # 5. Wrong role (Role 1 or 3) -> 403
    def test_05_wrong_role_denied(self):
        with self.assertRaises(HTTPException) as ctx:
            get_investigator_case_activity_summary(self.db, "CASE-2024-001", self.exp1)
        self.assertEqual(ctx.exception.status_code, 403)

        with self.assertRaises(HTTPException) as ctx2:
            get_investigator_case_activity_summary(self.db, "CASE-2024-001", self.adm1)
        self.assertEqual(ctx2.exception.status_code, 403)

    # 6. Empty case activity returns truthful baseline
    def test_06_empty_case_activity(self):
        summary = get_investigator_case_activity_summary(self.db, "CASE-2024-002", self.inv1)
        # Empty case has only case creation event, no fake evidence/reports
        self.assertEqual(summary.evidence_activity_count, 0)
        self.assertEqual(summary.report_activity_count, 0)
        self.assertEqual(summary.custody_activity_count, 0)
        self.assertEqual(summary.relationship_activity_count, 0)
        self.assertEqual(summary.case_activity_count, 1)

    # 7. Pagination works
    def test_07_pagination_works(self):
        page_1 = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, page=1, limit=2)
        page_2 = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, page=2, limit=2)
        self.assertEqual(len(page_1.activities), 2)
        self.assertNotEqual(page_1.activities[0].activity_id, page_2.activities[0].activity_id)
        self.assertEqual(page_1.page, 1)
        self.assertEqual(page_2.page, 2)

    # 8. Type / Module filters work
    def test_08_type_and_module_filters(self):
        custody_page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, activity_type="CUSTODY")
        for a in custody_page.activities:
            self.assertEqual(a.activity_type, "CUSTODY")

        rep_page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, activity_type="REPORT")
        for a in rep_page.activities:
            self.assertEqual(a.activity_type, "REPORT")

    # 9. Date filters work
    def test_09_date_filters(self):
        filter_start = datetime(2026, 9, 3, 0, 0, 0)
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, start_date=filter_start)
        for a in page.activities:
            self.assertGreaterEqual(a.timestamp, filter_start)

    # 10. Newest-first ordering works
    def test_10_newest_first_ordering(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, limit=50)
        timestamps = [a.timestamp for a in page.activities]
        self.assertEqual(timestamps, sorted(timestamps, reverse=True))

    # 11. Actor resolved from genuine User where available
    def test_11_actor_resolution(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, limit=50)
        ct_item = next(a for a in page.activities if a.action == "CASE_ASSIGNMENT")
        self.assertEqual(ct_item.actor_name, "Admin Alice")
        self.assertEqual(ct_item.actor_role, "Administrator")

    # 12. Evidence events case scoped
    def test_12_evidence_events_case_scoped(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, activity_type="EVIDENCE")
        for a in page.activities:
            self.assertEqual(a.case_id, "CASE-2024-001")

    # 13. Custody events case scoped
    def test_13_custody_events_case_scoped(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, activity_type="CUSTODY")
        for a in page.activities:
            self.assertEqual(a.case_id, "CASE-2024-001")

    # 14. Integrity events genuine only
    def test_14_integrity_events_genuine_only(self):
        summary = get_investigator_case_activity_summary(self.db, "CASE-2024-002", self.inv1)
        self.assertEqual(summary.integrity_activity_count, 0)

    # 15. EPRA events genuine only
    def test_15_epra_events_genuine_only(self):
        page_1 = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, activity_type="EPRA")
        self.assertGreaterEqual(len(page_1.activities), 1)

        page_empty = get_investigator_case_activity_timeline(self.db, "CASE-2024-002", self.inv1, activity_type="EPRA")
        self.assertEqual(len(page_empty.activities), 0)

    # 16. CBIR events genuine only
    def test_16_cbir_events_genuine_only(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, activity_type="CBIR")
        self.assertGreaterEqual(len(page.activities), 1)

    # 17. Relationship events genuine only
    def test_17_relationship_events_genuine_only(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, activity_type="RELATIONSHIP")
        self.assertGreaterEqual(len(page.activities), 1)
        self.assertEqual(page.activities[0].activity_type, "RELATIONSHIP")

    # 18. Report events genuine only
    def test_18_report_events_genuine_only(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, activity_type="REPORT")
        self.assertGreaterEqual(len(page.activities), 1)

    # 19. Duplicate events not returned twice (event_reference deduplication)
    def test_19_deduplication(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, limit=50)
        # Verify that EV-1001 upload is not duplicated
        upload_events = [a for a in page.activities if a.action == "EVIDENCE_UPLOADED" and a.evidence_id == "EV-1001"]
        self.assertEqual(len(upload_events), 1)

    # 20. View Details returns genuine source data
    def test_20_view_details_genuine_data(self):
        page = get_investigator_case_activity_timeline(self.db, "CASE-2024-001", self.inv1, limit=50)
        upload_ev = next(a for a in page.activities if a.evidence_id == "EV-1001")
        detail = get_investigator_case_activity_detail(self.db, "CASE-2024-001", upload_ev.activity_id, self.inv1)
        self.assertEqual(detail.activity_id, upload_ev.activity_id)
        self.assertIsNotNone(detail.evidence_details)
        self.assertEqual(detail.evidence_details["file_name"], "phishing_email.eml")
        self.assertIsNotNone(detail.integrity_details)
        self.assertEqual(detail.integrity_details["integrity_status"], "MATCH")

    # 21. Invalid activity ID returns 404
    def test_21_invalid_activity_id_404(self):
        with self.assertRaises(HTTPException) as ctx:
            get_investigator_case_activity_detail(self.db, "CASE-2024-001", "non_existent_act_id_999", self.inv1)
        self.assertEqual(ctx.exception.status_code, 404)


if __name__ == "__main__":
    unittest.main()
