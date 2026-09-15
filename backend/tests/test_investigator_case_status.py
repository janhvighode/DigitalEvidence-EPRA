"""
Comprehensive Test Suite for Investigator Case Status Backend Module.
Verifies all 17 required scenarios:
- TEST 1: Investigator A assigned CASE-6922 -> GET Case Status returns CASE-6922.
- TEST 2: Investigator B does not have CASE-6922 -> CASE-6922 must not appear.
- TEST 3: Fresh Investigator with no cases: all counts = 0, items = [].
- TEST 4: Evidence counts match actual persisted evidence records.
- TEST 5: Report status matches existing ReportRecord status.
- TEST 6: OPEN -> IN_PROGRESS transition succeeds.
- TEST 7: After transition: status history contains: OPEN -> IN_PROGRESS, correct user, timestamp, remark.
- TEST 8 (CRITICAL ADMIN SYNC TEST):
    Before: Admin Case Activity shows CASE-6922 under OPEN.
    Investigator changes: OPEN -> IN_PROGRESS.
    After: Admin Case Activity must show CASE-6922 under IN_PROGRESS WITHOUT a second Admin update.
- TEST 9: IN_PROGRESS -> UNDER_REVIEW succeeds when allowed.
- TEST 10: UNDER_REVIEW -> IN_PROGRESS succeeds for rework.
- TEST 11: UNDER_REVIEW -> CLOSED succeeds when closure requirements are satisfied.
- TEST 12: Invalid OPEN -> CLOSED transition is rejected (400 Bad Request).
- TEST 13: Unauthorized Investigator status change returns 403 Forbidden.
- TEST 14: Module readiness correctly handles NOT_APPLICABLE.
- TEST 15: Case progress and status remain separate.
- TEST 16: Regression check on Investigator Reports.
- TEST 17: Regression check on Metadata backend.
"""

import sys
import unittest
import uuid
from pathlib import Path
from datetime import datetime, timezone

# Add backend directory to sys.path
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException

from database.database import Base
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from models.possible_entity import PossibleEntity
from models.evidence_link import EvidenceLink
from models.case_timeline import CaseTimeline
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.report_record import ReportRecord
from models.case_status_history import CaseStatusHistory
from models.notification import Notification

from services.case_status_service import (
    get_investigator_case_status_board,
    get_investigator_case_status_detail,
    update_case_status_by_investigator,
    get_investigator_case_status_history
)
from services.case_activity_service import get_case_board


class TestInvestigatorCaseStatus(unittest.TestCase):

    def setUp(self):
        # In-memory SQLite database
        self.engine = create_engine("sqlite:///:memory:", echo=False)
        Base.metadata.create_all(
            bind=self.engine,
            tables=[
                Role.__table__,
                City.__table__,
                CyberCell.__table__,
                User.__table__,
                Case.__table__,
                Evidence.__table__,
                EvidenceHash.__table__,
                EPRAResult.__table__,
                CBIRResult.__table__,
                PossibleEntity.__table__,
                EvidenceLink.__table__,
                CaseTimeline.__table__,
                CustodyLog.__table__,
                ActivityLog.__table__,
                ReportRecord.__table__,
                CaseStatusHistory.__table__,
                Notification.__table__,
            ]
        )
        self.Session = sessionmaker(bind=self.engine)
        self.db = self.Session()

        # Seed roles
        self.role_admin = Role(id=1, role_name="Administrator")
        self.role_inv = Role(id=2, role_name="Investigator")
        self.role_exp = Role(id=3, role_name="Cyber Expert")
        self.db.add_all([self.role_admin, self.role_inv, self.role_exp])

        # Seed city & cyber cell
        self.city = City(id=1, city_name="Cyber City")
        self.cell = CyberCell(id=1, cyber_cell_name="Headquarters Cell", admin_email="admin@deps.gov", city_id=1)
        self.db.add_all([self.city, self.cell])

        # Seed Admin user
        self.admin = User(
            id=1,
            full_name="Admin Chief",
            username="admin_chief",
            email="admin@deps.gov",
            password="hashed_pw",
            phone_number="1234567890",
            role_id=1,
            cyber_cell_id=1,
            is_active=True
        )

        # Seed Investigator A
        self.inv_a = User(
            id=2,
            full_name="Investigator Alice",
            username="alice_inv",
            email="alice@deps.gov",
            password="hashed_pw",
            phone_number="1234567891",
            role_id=2,
            cyber_cell_id=1,
            is_active=True
        )

        # Seed Investigator B
        self.inv_b = User(
            id=3,
            full_name="Investigator Bob",
            username="bob_inv",
            email="bob@deps.gov",
            password="hashed_pw",
            phone_number="1234567892",
            role_id=2,
            cyber_cell_id=1,
            is_active=True
        )

        # Seed Fresh Investigator C
        self.inv_c = User(
            id=4,
            full_name="Investigator Charlie",
            username="charlie_inv",
            email="charlie@deps.gov",
            password="hashed_pw",
            phone_number="1234567893",
            role_id=2,
            cyber_cell_id=1,
            is_active=True
        )

        # Seed Cyber Expert
        self.expert = User(
            id=5,
            full_name="Expert Dave",
            username="dave_expert",
            email="dave@deps.gov",
            password="hashed_pw",
            phone_number="1234567894",
            role_id=3,
            cyber_cell_id=1,
            is_active=True
        )

        self.db.add_all([self.admin, self.inv_a, self.inv_b, self.inv_c, self.expert])

        # Seed CASE-6922 assigned to Investigator A
        self.case_6922 = Case(
            id=10,
            case_id="CASE-6922",
            title="Corporate Ransomware Incident",
            description="Financial extortion and crypto malware",
            investigator_id=self.inv_a.id,
            cyber_expert_id=self.expert.id,
            priority="High",
            status="Open",
            created_by=self.admin.id
        )
        self.db.add(self.case_6922)
        self.db.commit()

    def tearDown(self):
        self.db.close()
        Base.metadata.drop_all(bind=self.engine)

    # --------------------------------------------------------------------------
    # TEST 1 & TEST 2: Assignment Isolation
    # --------------------------------------------------------------------------
    def test_01_and_02_investigator_case_assignment_scoping(self):
        # TEST 1: Investigator A has CASE-6922
        board_a = get_investigator_case_status_board(self.db, self.inv_a)
        case_ids_a = [c.case_id for c in board_a.cases]
        self.assertIn("CASE-6922", case_ids_a)
        self.assertEqual(board_a.open_count, 1)
        self.assertEqual(board_a.total_cases, 1)

        # TEST 2: Investigator B does not have CASE-6922
        board_b = get_investigator_case_status_board(self.db, self.inv_b)
        case_ids_b = [c.case_id for c in board_b.cases]
        self.assertNotIn("CASE-6922", case_ids_b)
        self.assertEqual(board_b.total_cases, 0)

    # --------------------------------------------------------------------------
    # TEST 3: Fresh Investigator with No Cases
    # --------------------------------------------------------------------------
    def test_03_fresh_investigator_empty_state(self):
        board_c = get_investigator_case_status_board(self.db, self.inv_c)
        self.assertEqual(board_c.open_count, 0)
        self.assertEqual(board_c.in_progress_count, 0)
        self.assertEqual(board_c.under_review_count, 0)
        self.assertEqual(board_c.closed_count, 0)
        self.assertEqual(board_c.total_cases, 0)
        self.assertEqual(len(board_c.cases), 0)
        self.assertEqual(len(board_c.sections["OPEN"]), 0)
        self.assertEqual(len(board_c.sections["IN_PROGRESS"]), 0)
        self.assertEqual(len(board_c.sections["UNDER_REVIEW"]), 0)
        self.assertEqual(len(board_c.sections["CLOSED"]), 0)

    # --------------------------------------------------------------------------
    # TEST 4: Evidence Counts Match Persisted Evidence
    # --------------------------------------------------------------------------
    def test_04_evidence_counts_calculation(self):
        # Add 3 evidence items to CASE-6922
        ev1 = Evidence(id=1, evidence_id="EV-001", case_id=self.case_6922.id, file_name="disk.raw", file_type="binary/raw", file_size=1024, file_path="/data/ev1")
        ev2 = Evidence(id=2, evidence_id="EV-002", case_id=self.case_6922.id, file_name="pcap.pcap", file_type="network/pcap", file_size=2048, file_path="/data/ev2")
        ev3 = Evidence(id=3, evidence_id="EV-003", case_id=self.case_6922.id, file_name="ram.bin", file_type="memory/bin", file_size=4096, file_path="/data/ev3")
        self.db.add_all([ev1, ev2, ev3])

        # EV-001 analyzed with EPRA COMPLETE
        epra1 = EPRAResult(id=1, evidence_id=1, case_id=self.case_6922.id, epra_score=85.0, priority="High", analysis_status="COMPLETE")
        self.db.add(epra1)

        # EV-002 has an integrity mismatch
        hash2 = EvidenceHash(
            id=1,
            evidence_id=2,
            file_name="pcap.pcap",
            sha256_hash="abc",
            current_hash="xyz",
            original_hash="abc",
            hash_match=False,
            tampered=True,
            integrity_status="TAMPERED"
        )
        self.db.add(hash2)
        self.db.commit()

        board = get_investigator_case_status_board(self.db, self.inv_a)
        case_item = board.cases[0]

        self.assertEqual(case_item.total_evidence_collected, 3)
        self.assertEqual(case_item.evidence_analyzed, 1)
        self.assertEqual(case_item.pending_analysis, 2)
        self.assertEqual(case_item.integrity_issues, 1)

    # --------------------------------------------------------------------------
    # TEST 5: Report Status Matches Persisted ReportRecord
    # --------------------------------------------------------------------------
    def test_05_report_status_integration(self):
        # Initial: No report
        board1 = get_investigator_case_status_board(self.db, self.inv_a)
        self.assertEqual(board1.cases[0].report_status, "NOT_GENERATED")

        # Create Draft Report
        draft = ReportRecord(
            id=str(uuid.uuid4()),
            case_id="CASE-6922",
            case_title="Corporate Ransomware Incident",
            investigator_name="Investigator Alice",
            report_type="Forensic Report",
            file_path="/reports/draft.pdf",
            file_name="draft.pdf",
            is_draft=True
        )
        self.db.add(draft)
        self.db.commit()

        board2 = get_investigator_case_status_board(self.db, self.inv_a)
        self.assertEqual(board2.cases[0].report_status, "DRAFT")

        # Create Finalized / Generated Report
        final_rep = ReportRecord(
            id=str(uuid.uuid4()),
            case_id="CASE-6922",
            case_title="Corporate Ransomware Incident",
            investigator_name="Investigator Alice",
            report_type="Forensic Report",
            file_path="/reports/final.pdf",
            file_name="final.pdf",
            is_draft=False
        )
        self.db.add(final_rep)
        self.db.commit()

        board3 = get_investigator_case_status_board(self.db, self.inv_a)
        self.assertEqual(board3.cases[0].report_status, "GENERATED")

        # If case is Closed, report status is FINAL
        self.case_6922.status = "Closed"
        self.db.commit()
        board4 = get_investigator_case_status_board(self.db, self.inv_a)
        self.assertEqual(board4.cases[0].report_status, "FINAL")

        # Reset back to Open
        self.case_6922.status = "Open"
        self.db.commit()

    # --------------------------------------------------------------------------
    # TEST 6 & TEST 7: Transition OPEN -> IN_PROGRESS & Audit History
    # --------------------------------------------------------------------------
    def test_06_and_07_open_to_in_progress_and_history(self):
        res = update_case_status_by_investigator(
            db=self.db,
            case_identifier="CASE-6922",
            new_status_raw="IN_PROGRESS",
            remark="Beginning evidence extraction and analysis.",
            current_user=self.inv_a
        )
        self.assertEqual(res["previous_status"], "OPEN")
        self.assertEqual(res["current_status"], "IN_PROGRESS")

        # Persisted Case.status is updated
        self.db.refresh(self.case_6922)
        self.assertEqual(self.case_6922.status, "In Progress")

        # TEST 7: Status history record
        history = get_investigator_case_status_history(self.db, "CASE-6922", self.inv_a)
        self.assertEqual(len(history), 1)
        h = history[0]
        self.assertEqual(h.case_id, "CASE-6922")
        self.assertEqual(h.old_status, "OPEN")
        self.assertEqual(h.new_status, "IN_PROGRESS")
        self.assertEqual(h.changed_by_user_id, self.inv_a.id)
        self.assertEqual(h.changed_by_role, "Investigator")
        self.assertEqual(h.remark, "Beginning evidence extraction and analysis.")
        self.assertIsNotNone(h.changed_at)

    # --------------------------------------------------------------------------
    # TEST 8: CRITICAL ADMIN SYNC TEST
    # --------------------------------------------------------------------------
    def test_08_critical_administrator_case_activity_sync(self):
        """
        Verifies that when Investigator transitions CASE-6922 from OPEN to IN_PROGRESS,
        the Administrator Case Activity Kanban board immediately moves CASE-6922
        from 'Open' to 'In Progress' on its next GET request WITHOUT any second Admin action.
        """
        # Step 1: Admin views board initially -> CASE-6922 is under 'Open'
        admin_board_before = get_case_board(self.db, self.admin)
        open_ids_before = [c["case_id"] for c in admin_board_before["Open"]]
        in_progress_ids_before = [c["case_id"] for c in admin_board_before["In Progress"]]

        self.assertIn("CASE-6922", open_ids_before)
        self.assertNotIn("CASE-6922", in_progress_ids_before)

        # Step 2: Investigator updates CASE-6922: OPEN -> IN_PROGRESS
        update_case_status_by_investigator(
            db=self.db,
            case_identifier="CASE-6922",
            new_status_raw="IN_PROGRESS",
            remark="Investigator transitioning to In Progress",
            current_user=self.inv_a
        )

        # Step 3: Admin calls get_case_board WITHOUT any admin updates
        admin_board_after = get_case_board(self.db, self.admin)
        open_ids_after = [c["case_id"] for c in admin_board_after["Open"]]
        in_progress_ids_after = [c["case_id"] for c in admin_board_after["In Progress"]]

        # Step 4: Verify automatic synchronization
        self.assertNotIn("CASE-6922", open_ids_after, "CASE-6922 must NOT be in Admin 'Open' column anymore")
        self.assertIn("CASE-6922", in_progress_ids_after, "CASE-6922 must automatically appear in Admin 'In Progress' column")

    # --------------------------------------------------------------------------
    # TEST 9, 10, 11: Valid Transitions (IN_PROGRESS -> UNDER_REVIEW -> IN_PROGRESS -> CLOSED)
    # --------------------------------------------------------------------------
    def test_09_10_11_workflow_transitions(self):
        # 1. OPEN -> IN_PROGRESS
        update_case_status_by_investigator(self.db, "CASE-6922", "IN_PROGRESS", "Start", self.inv_a)
        self.db.refresh(self.case_6922)
        self.assertEqual(self.case_6922.status, "In Progress")

        # 2. IN_PROGRESS -> UNDER_REVIEW (TEST 9)
        update_case_status_by_investigator(self.db, "CASE-6922", "UNDER_REVIEW", "Ready for review", self.inv_a)
        self.db.refresh(self.case_6922)
        self.assertEqual(self.case_6922.status, "Under Review")

        # 3. UNDER_REVIEW -> IN_PROGRESS for rework (TEST 10)
        update_case_status_by_investigator(self.db, "CASE-6922", "IN_PROGRESS", "Rework requested", self.inv_a)
        self.db.refresh(self.case_6922)
        self.assertEqual(self.case_6922.status, "In Progress")

        # Return to UNDER_REVIEW
        update_case_status_by_investigator(self.db, "CASE-6922", "UNDER_REVIEW", "Rework complete", self.inv_a)

        # 4. UNDER_REVIEW -> CLOSED (TEST 11)
        update_case_status_by_investigator(self.db, "CASE-6922", "CLOSED", "Investigation closed", self.inv_a)
        self.db.refresh(self.case_6922)
        self.assertEqual(self.case_6922.status, "Closed")

        # Status history contains all 5 transitions in reverse chronological order
        hist = get_investigator_case_status_history(self.db, "CASE-6922", self.inv_a)
        self.assertEqual(len(hist), 5)
        self.assertEqual(hist[0].new_status, "CLOSED")
        self.assertEqual(hist[1].new_status, "UNDER_REVIEW")
        self.assertEqual(hist[2].new_status, "IN_PROGRESS")
        self.assertEqual(hist[3].new_status, "UNDER_REVIEW")
        self.assertEqual(hist[4].new_status, "IN_PROGRESS")

    # --------------------------------------------------------------------------
    # TEST 12: Invalid Transitions Rejected
    # --------------------------------------------------------------------------
    def test_12_invalid_transitions_rejected(self):
        # Case is currently OPEN
        self.assertEqual(self.case_6922.status, "Open")

        # Attempt OPEN -> CLOSED (forbidden)
        with self.assertRaises(HTTPException) as ctx1:
            update_case_status_by_investigator(self.db, "CASE-6922", "CLOSED", "Direct close", self.inv_a)
        self.assertEqual(ctx1.exception.status_code, 400)
        self.assertIn("not allowed", ctx1.exception.detail)

        # Attempt OPEN -> UNDER_REVIEW (forbidden)
        with self.assertRaises(HTTPException) as ctx2:
            update_case_status_by_investigator(self.db, "CASE-6922", "UNDER_REVIEW", "Direct review", self.inv_a)
        self.assertEqual(ctx2.exception.status_code, 400)

        # Status remains untouched
        self.db.refresh(self.case_6922)
        self.assertEqual(self.case_6922.status, "Open")

    # --------------------------------------------------------------------------
    # TEST 13: Unauthorized Investigator Access Rejected
    # --------------------------------------------------------------------------
    def test_13_unauthorized_access_rejected(self):
        # Investigator B attempts to change status of CASE-6922 (assigned to A)
        with self.assertRaises(HTTPException) as ctx:
            update_case_status_by_investigator(self.db, "CASE-6922", "IN_PROGRESS", "Hacking status", self.inv_b)
        self.assertEqual(ctx.exception.status_code, 403)
        self.assertIn("Access denied", ctx.exception.detail)

        # Non-investigator (Admin) calling investigator endpoint -> 403
        with self.assertRaises(HTTPException) as ctx_admin:
            update_case_status_by_investigator(self.db, "CASE-6922", "IN_PROGRESS", "Admin call", self.admin)
        self.assertEqual(ctx_admin.exception.status_code, 403)

    # --------------------------------------------------------------------------
    # TEST 14: Module Readiness Handles NOT_APPLICABLE
    # --------------------------------------------------------------------------
    def test_14_module_readiness_not_applicable(self):
        # Add 1 text file (non-image)
        ev = Evidence(id=1, evidence_id="EV-LOG", case_id=self.case_6922.id, file_name="server.log", file_type="text/plain", file_size=512, file_path="/data/log")
        self.db.add(ev)
        self.db.commit()

        detail = get_investigator_case_status_detail(self.db, "CASE-6922", self.inv_a)
        mr = detail.module_readiness

        # CBIR must be NOT_APPLICABLE because no image files exist
        self.assertEqual(mr["cbir"], "NOT_APPLICABLE")

        # Relationship analysis must be NOT_APPLICABLE because only 1 evidence item exists
        self.assertEqual(mr["relationship_analysis"], "NOT_APPLICABLE")

    # --------------------------------------------------------------------------
    # TEST 15: Case Progress and Status Remain Separate
    # --------------------------------------------------------------------------
    def test_15_progress_and_status_remain_separate(self):
        # Case is IN_PROGRESS
        update_case_status_by_investigator(self.db, "CASE-6922", "IN_PROGRESS", "Starting", self.inv_a)

        # Add evidence
        ev = Evidence(id=10, evidence_id="EV-10", case_id=self.case_6922.id, file_name="doc.pdf", file_type="application/pdf", file_size=1024, file_path="/p")
        self.db.add(ev)
        self.db.commit()

        detail = get_investigator_case_status_detail(self.db, "CASE-6922", self.inv_a)
        # Status is IN_PROGRESS
        self.assertEqual(detail.case_information.current_status, "IN_PROGRESS")
        # Investigation progress is a distinct number (e.g. 60% based on registered + evidence + verified milestones)
        self.assertEqual(detail.investigation_progress, 60)
        self.assertNotEqual(str(detail.investigation_progress), detail.case_information.current_status)

    # --------------------------------------------------------------------------
    # TEST 16 & 17: Regressions on Reports & Metadata
    # --------------------------------------------------------------------------
    def test_16_no_regression_reports(self):
        # Ensure report service imports and functions work without regression
        from services.report_service import get_investigator_reports_overview, get_investigator_reports_trend
        overview = get_investigator_reports_overview(self.db, self.inv_a)
        self.assertIn("total_reports", overview)
        trend = get_investigator_reports_trend(self.db, self.inv_a)
        self.assertEqual(len(trend), 6)

    def test_17_no_regression_metadata(self):
        # Ensure metadata service imports cleanly
        from services.metadata_service import MetadataService
        self.assertTrue(callable(MetadataService.get_metadata_table))

    # --------------------------------------------------------------------------
    # TEST 18: FastAPI Route Handlers Layer
    # --------------------------------------------------------------------------
    def test_18_route_handlers_layer(self):
        from routes.case_status_routes import (
            fetch_case_status_board,
            fetch_case_status_detail,
            change_case_status,
            fetch_case_status_history,
            verify_investigator
        )
        from schemas.case_status import CaseStatusUpdateRequest

        # 1. fetch_case_status_board
        board = fetch_case_status_board(
            search=None,
            status=None,
            priority=None,
            case_health=None,
            report_status=None,
            page=1,
            page_size=10,
            current_user=self.inv_a,
            db=self.db
        )
        self.assertEqual(board.open_count, 1)
        self.assertEqual(len(board.sections["OPEN"]), 1)
        self.assertEqual(board.sections["OPEN"][0].case_id, "CASE-6922")

        # 2. fetch_case_status_detail
        detail = fetch_case_status_detail(
            case_id="CASE-6922",
            current_user=self.inv_a,
            db=self.db
        )
        self.assertEqual(detail.case_information.case_id, "CASE-6922")
        self.assertIn("module_readiness", detail.__dict__)
        self.assertIn("evidence_summary", detail.__dict__)

        # 3. change_case_status
        patch_res = change_case_status(
            case_id="CASE-6922",
            payload=CaseStatusUpdateRequest(new_status="IN_PROGRESS", remark="Route layer transition"),
            current_user=self.inv_a,
            db=self.db
        )
        self.assertEqual(patch_res["current_status"], "IN_PROGRESS")
        self.assertEqual(patch_res["previous_status"], "OPEN")

        # 4. fetch_case_status_history
        history = fetch_case_status_history(
            case_id="CASE-6922",
            current_user=self.inv_a,
            db=self.db
        )
        self.assertGreaterEqual(len(history), 1)
        self.assertEqual(history[0].new_status, "IN_PROGRESS")
        self.assertEqual(history[0].remark, "Route layer transition")

        # 5. verify_investigator role enforcement
        with self.assertRaises(HTTPException) as ctx:
            verify_investigator(self.admin)
        self.assertEqual(ctx.exception.status_code, 403)


if __name__ == "__main__":
    unittest.main()

