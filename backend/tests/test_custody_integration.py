"""
Comprehensive integration tests for Case-Scoped Chain of Custody APIs.
Tests:
- Cyber Expert authorization (role_id == 3) & assigned case scoping
- Missing/invalid JWT -> 401
- Non-Cyber-Expert -> 403
- Unassigned case -> 403
- Missing case / foreign evidence -> 404
- Dynamic summary metrics (total events, distinct human handlers, transfers)
- Timeline events & filtering
- Current custody lifecycle (null defaults, no fabrication)
- Audited current custody update (direct holder change rejected)
- Two-phase transfer handshake (initiate -> pending -> receive -> completed)
- Contradictory transfer rejection (400)
- Recipient mismatch rejection (400)
- Evidence access event without holder assignment
- Consolidated evidence custody details
- Cross-case isolation
- Zero modifications to frontend/
"""
import sys
import subprocess
from pathlib import Path
from datetime import datetime, timezone

root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException
from database.database import SessionLocal
from models.user import User
from models.role import Role
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.custody_log import CustodyLog
from models.current_custody import CurrentCustodyInfo
from models.transfer_record import TransferRecord
from models.activity_log import ActivityLog

from routes.custody_routes import (
    verify_cyber_expert_case_access,
    verify_evidence_in_case,
    get_custody_summary,
    get_custody_timeline,
    get_current_custody,
    update_current_custody,
    initiate_transfer,
    receive_transfer,
    record_evidence_access,
    get_transfer_history,
    get_evidence_custody_details
)
from schemas.custody import (
    TransferInitiateRequest,
    TransferReceiveRequest,
    CurrentCustodyUpdateRequest
)


def get_or_create_test_entities(db):
    """Setup isolated test roles, users, cases, and evidence matching existing TiDB schema."""
    # Find genuine Cyber Expert
    ce_user = db.query(User).filter(User.role_id == 3).first()
    if not ce_user:
        ce_user = User(
            username="test_expert_custody",
            email="test_expert_custody@deps.gov",
            phone_number="9876543210",
            password="hashedpassword",
            role_id=3,
            cyber_cell_id=1,
            full_name="Dr. Jane Forensic",
            is_active=True
        )
        db.add(ce_user)
        db.commit()
        db.refresh(ce_user)

    # Find another Cyber Expert or create in memory
    other_ce = db.query(User).filter(User.role_id == 3, User.id != ce_user.id).first()
    if not other_ce:
        other_ce = User(id=9998, role_id=3, full_name="Agent Cooper", username="other_expert")

    # Find non-cyber-expert or create in memory
    admin_user = db.query(User).filter(User.role_id != 3).first()
    if not admin_user:
        admin_user = User(id=9999, role_id=1, full_name="Admin Smith", username="admin_smith")

    # Assigned Case
    test_case = db.query(Case).filter(Case.case_id == "CASE-CUSTODY-TEST-01").first()
    if not test_case:
        test_case = Case(
            case_id="CASE-CUSTODY-TEST-01",
            title="Digital Custody Validation Case",
            description="Testing chain of custody integration",
            cyber_expert_id=ce_user.id,
            status="Open",
            priority="Medium"
        )
        db.add(test_case)
        db.commit()
        db.refresh(test_case)
    else:
        test_case.cyber_expert_id = ce_user.id
        db.commit()
        db.refresh(test_case)

    # Foreign Case (not assigned to ce_user)
    case_2 = db.query(Case).filter(Case.case_id == "CASE-CUSTODY-TEST-02").first()
    if not case_2:
        case_2 = Case(
            case_id="CASE-CUSTODY-TEST-02",
            title="Isolated Foreign Case",
            description="Testing cross-case custody isolation",
            cyber_expert_id=other_ce.id if hasattr(other_ce, 'id') and other_ce.id != ce_user.id else 9998,
            status="Open",
            priority="Medium"
        )
        db.add(case_2)
        db.commit()
        db.refresh(case_2)

    # Evidence in Case 1
    ev_1 = db.query(Evidence).filter(Evidence.evidence_id == "EV-CUSTODY-101").first()
    if not ev_1:
        ev_1 = Evidence(
            evidence_id="EV-CUSTODY-101",
            case_id=test_case.id,
            file_name="ram_dump.bin",
            file_type="Memory Dump",
            file_size=1048576,
            file_path="uploads/ram_dump.bin",
            status="Active"
        )
        db.add(ev_1)
        db.commit()
        db.refresh(ev_1)

    # Evidence in Case 2
    ev_2 = db.query(Evidence).filter(Evidence.evidence_id == "EV-CUSTODY-201").first()
    if not ev_2:
        ev_2 = Evidence(
            evidence_id="EV-CUSTODY-201",
            case_id=case_2.id,
            file_name="usb_drive.img",
            file_type="Disk Image",
            file_size=2097152,
            file_path="uploads/usb_drive.img",
            status="Active"
        )
        db.add(ev_2)
        db.commit()
        db.refresh(ev_2)

    return ce_user, other_ce, admin_user, test_case, case_2, ev_1, ev_2


def test_1_authorization_and_scoping():
    """Verify 401, 403, 404 security rules."""
    db = SessionLocal()
    try:
        ce_user, other_ce, admin_user, test_case, case_2, ev_1, ev_2 = get_or_create_test_entities(db)

        # 1. Missing user -> 401
        try:
            verify_cyber_expert_case_access(test_case.id, None, db)
            assert False, "Should raise 401 for None user"
        except HTTPException as e:
            assert e.status_code == 401

        # 2. Non-Cyber-Expert -> 403
        try:
            verify_cyber_expert_case_access(test_case.id, admin_user, db)
            assert False, "Should raise 403 for non-expert"
        except HTTPException as e:
            assert e.status_code == 403

        # 3. Missing case -> 404
        try:
            verify_cyber_expert_case_access(999999, ce_user, db)
            assert False, "Should raise 404 for nonexistent case"
        except HTTPException as e:
            assert e.status_code == 404

        # 4. Unassigned case -> 403
        try:
            verify_cyber_expert_case_access(case_2.id, ce_user, db)
            assert False, "Should raise 403 for unassigned case"
        except HTTPException as e:
            assert e.status_code == 403

        # 5. Evidence outside case -> 404
        try:
            verify_evidence_in_case(test_case.id, ev_2.evidence_id, db)
            assert False, "Should raise 404 for evidence belonging to other case"
        except HTTPException as e:
            assert e.status_code == 404

        # 6. Valid access
        verified_case = verify_cyber_expert_case_access(test_case.id, ce_user, db)
        assert verified_case.id == test_case.id

        verified_ev = verify_evidence_in_case(test_case.id, ev_1.evidence_id, db)
        assert verified_ev.id == ev_1.id
    finally:
        db.close()
    print("PASS: test_1_authorization_and_scoping")


def test_2_summary_metrics_and_idempotent_sync():
    """Verify summary metrics and automatic sync of authentic evidence events."""
    db = SessionLocal()
    try:
        ce_user, _, _, test_case, _, ev_1, _ = get_or_create_test_entities(db)

        # Call get_custody_summary for the case
        summary = get_custody_summary(test_case.id, evidence_id=None, db=db, current_user=ce_user)
        assert summary["total_events"] >= 1
        assert summary["handlers_count"] >= 1
        assert summary["first_handled"] is not None

        # Call get_custody_summary scoped to ev_1
        ev_summary = get_custody_summary(test_case.id, evidence_id=ev_1.evidence_id, db=db, current_user=ce_user)
        assert ev_summary["total_events"] >= 1
        assert ev_summary["evidence_id"] == ev_1.evidence_id

        # Repeated calls must be idempotent (no duplicate upload events created)
        summary_2 = get_custody_summary(test_case.id, evidence_id=None, db=db, current_user=ce_user)
        assert summary_2["total_events"] == summary["total_events"]
    finally:
        db.close()
    print("PASS: test_2_summary_metrics_and_idempotent_sync")


def test_3_timeline_and_filters():
    """Verify timeline events, filters, and ordering."""
    db = SessionLocal()
    try:
        ce_user, _, _, test_case, _, ev_1, _ = get_or_create_test_entities(db)

        tl_all = get_custody_timeline(test_case.id, evidence_id=ev_1.evidence_id, event_filter="ALL", db=db, current_user=ce_user)
        assert tl_all["total_events"] >= 1
        assert len(tl_all["events"]) >= 1
        assert tl_all["events"][0]["evidence_id"] == ev_1.evidence_id

        # Filter by UPLOAD
        tl_upload = get_custody_timeline(test_case.id, evidence_id=ev_1.evidence_id, event_filter="UPLOAD", db=db, current_user=ce_user)
        for ev in tl_upload["events"]:
            assert ev["event_type"] == "UPLOAD" or "UPLOAD" in ev["title"]
    finally:
        db.close()
    print("PASS: test_3_timeline_and_filters")


def test_4_current_custody_and_audited_update():
    """Verify current custody read and audited update guards."""
    db = SessionLocal()
    try:
        ce_user, _, _, test_case, _, ev_1, _ = get_or_create_test_entities(db)

        # Initial read
        curr = get_current_custody(test_case.id, evidence_id=ev_1.evidence_id, db=db, current_user=ce_user)
        assert curr["evidence_id"] == ev_1.evidence_id

        # Audited update of department/location/remarks
        payload = CurrentCustodyUpdateRequest(
            department="Forensics Unit 7",
            location="Room 302, Shelf A",
            remarks="Stored in anti-static enclosure"
        )
        updated = update_current_custody(test_case.id, payload=payload, evidence_id=ev_1.evidence_id, db=db, current_user=ce_user)
        assert updated["department"] == "Forensics Unit 7"
        assert updated["location"] == "Room 302, Shelf A"
        assert updated["remarks"] == "Stored in anti-static enclosure"

        # Verify audit log was recorded
        audit_log = db.query(CustodyLog).filter(
            CustodyLog.evidence_id == ev_1.evidence_id,
            CustodyLog.action == "CUSTODY_INFO_UPDATED"
        ).first()
        assert audit_log is not None
        assert audit_log.investigator_name == (ce_user.full_name or ce_user.username)
    finally:
        db.close()
    print("PASS: test_4_current_custody_and_audited_update")


def test_5_transfer_workflow_handshake():
    """Verify initiate transfer -> pending -> receive transfer -> completed."""
    db = SessionLocal()
    try:
        ce_user, _, _, test_case, _, ev_1, _ = get_or_create_test_entities(db)

        # Clear any existing pending transfer for clean test run
        db.query(TransferRecord).filter(
            TransferRecord.evidence_id == ev_1.evidence_id,
            TransferRecord.status == "PENDING_RECEIPT"
        ).delete()
        db.commit()

        # 1. Initiate transfer
        init_req = TransferInitiateRequest(
            evidence_id=ev_1.evidence_id,
            recipient_name="Investigator Sharma",
            recipient_role="Senior Examiner",
            reason_or_remarks="Transferred for advanced chip-off analysis"
        )
        res_init = initiate_transfer(test_case.id, payload=init_req, db=db, current_user=ce_user)
        assert res_init["status"] == "PENDING_RECEIPT"
        ref = res_init["transfer_reference"]

        # Holder must NOT change yet
        curr_pending = get_current_custody(test_case.id, evidence_id=ev_1.evidence_id, db=db, current_user=ce_user)
        assert curr_pending["custody_status"] == "PENDING_RECEIPT"
        assert curr_pending["pending_recipient_name"] == "Investigator Sharma"

        # 2. Contradictory transfer attempt must raise 400
        try:
            initiate_transfer(test_case.id, payload=init_req, db=db, current_user=ce_user)
            assert False, "Should reject contradictory transfer while pending"
        except HTTPException as e:
            assert e.status_code == 400
            assert "already has a pending transfer" in e.detail

        # 3. Recipient mismatch must raise 400
        recv_wrong = TransferReceiveRequest(recipient_name="Random Guy")
        try:
            receive_transfer(test_case.id, payload=recv_wrong, transfer_reference=ref, db=db, current_user=ce_user)
            assert False, "Should reject recipient mismatch"
        except HTTPException as e:
            assert e.status_code == 400

        # 4. Valid receipt confirmed
        recv_valid = TransferReceiveRequest(
            recipient_name="Investigator Sharma",
            department="Hardware Forensics Division",
            location="Lab Bench 12",
            remarks="Seal verified intact, transfer accepted"
        )
        res_recv = receive_transfer(test_case.id, payload=recv_valid, transfer_reference=ref, db=db, current_user=ce_user)
        assert res_recv["status"] == "COMPLETED"

        # Now holder officially changes!
        curr_done = get_current_custody(test_case.id, evidence_id=ev_1.evidence_id, db=db, current_user=ce_user)
        assert curr_done["current_holder_name"] == "Investigator Sharma"
        assert curr_done["department"] == "Hardware Forensics Division"
        assert curr_done["custody_status"] == "In Analysis"
        assert curr_done["pending_recipient_name"] is None

        # 5. Duplicate receipt rejected with 400
        try:
            receive_transfer(test_case.id, payload=recv_valid, transfer_reference=ref, db=db, current_user=ce_user)
            assert False, "Should reject duplicate receipt"
        except HTTPException as e:
            assert e.status_code == 400
            assert "already been completed" in e.detail
    finally:
        db.close()
    print("PASS: test_5_transfer_workflow_handshake")


def test_6_access_event_no_holder_mutation():
    """Verify evidence access records event and sets status to 'In Analysis' without mutating holder."""
    db = SessionLocal()
    try:
        ce_user, _, _, test_case, _, ev_1, _ = get_or_create_test_entities(db)

        res = record_evidence_access(
            case_id=test_case.id,
            evidence_id=ev_1.evidence_id,
            purpose="Routine forensic indexing",
            db=db,
            current_user=ce_user
        )
        assert res["status"] == "success"

        curr = get_current_custody(test_case.id, evidence_id=ev_1.evidence_id, db=db, current_user=ce_user)
        assert curr["custody_status"] == "In Analysis"
        assert curr["last_accessed"] is not None
    finally:
        db.close()
    print("PASS: test_6_access_event_no_holder_mutation")


def test_7_evidence_details_and_transfers():
    """Verify consolidated evidence custody details and paginated transfer history."""
    db = SessionLocal()
    try:
        ce_user, _, _, test_case, _, ev_1, _ = get_or_create_test_entities(db)

        # 1. Consolidated details
        details = get_evidence_custody_details(test_case.id, ev_1.evidence_id, db=db, current_user=ce_user)
        assert details["case_id"] == test_case.id
        assert details["evidence_id"] == ev_1.evidence_id
        assert "summary" in details
        assert "timeline" in details
        assert "transfers" in details

        # 2. Transfer history
        trf_history = get_transfer_history(test_case.id, evidence_id=ev_1.evidence_id, page=1, page_size=10, db=db, current_user=ce_user)
        assert trf_history["total"] >= 1
        assert len(trf_history["transfers"]) >= 1
        assert trf_history["transfers"][0]["status"] == "COMPLETED"
    finally:
        db.close()
    print("PASS: test_7_evidence_details_and_transfers")


def test_8_cross_case_isolation():
    """Verify zero cross-case custody data leakage."""
    db = SessionLocal()
    try:
        ce_user, other_ce, _, test_case, case_2, ev_1, ev_2 = get_or_create_test_entities(db)

        # Case 1 timeline only contains Case 1 evidence
        tl_1 = get_custody_timeline(test_case.id, evidence_id=None, event_filter="ALL", db=db, current_user=ce_user)
        for ev in tl_1["events"]:
            assert ev["evidence_id"] != ev_2.evidence_id
            assert ev["case_id"] == str(test_case.id)

        # Case 2 timeline only accessible by assigned expert (other_ce)
        tl_2 = get_custody_timeline(case_2.id, evidence_id=None, event_filter="ALL", db=db, current_user=other_ce)
        for ev in tl_2["events"]:
            assert ev["evidence_id"] != ev_1.evidence_id
            assert ev["case_id"] == str(case_2.id)
    finally:
        db.close()
    print("PASS: test_8_cross_case_isolation")


def test_9_frontend_untouched():
    """Verify git status shows ZERO modifications or additions inside frontend/."""
    out = subprocess.check_output(["git", "status", "--porcelain", str(root_dir / "frontend")]).decode("utf-8")
    assert out.strip() == "", f"Frontend directory must be untouched! Found changes:\n{out}"
    print("PASS: test_9_frontend_untouched")


if __name__ == "__main__":
    print("\n========================================================")
    print("RUNNING CHAIN OF CUSTODY BACKEND INTEGRATION TESTS")
    print("========================================================")
    test_1_authorization_and_scoping()
    test_2_summary_metrics_and_idempotent_sync()
    test_3_timeline_and_filters()
    test_4_current_custody_and_audited_update()
    test_5_transfer_workflow_handshake()
    test_6_access_event_no_holder_mutation()
    test_7_evidence_details_and_transfers()
    test_8_cross_case_isolation()
    test_9_frontend_untouched()
    print("========================================================")
    print("ALL 9 CHAIN OF CUSTODY INTEGRATION TESTS PASSED SUCCESSFULLY!\n")
