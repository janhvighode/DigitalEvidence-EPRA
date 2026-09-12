"""
Tests for Deepak's Chain of Custody lifecycle and transfer state machine.
Uses isolated SQLite in-memory database to verify Deepak's core business logic.
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
from models.evidence_record import EvidenceRecord
from models.custody_log import CustodyLog
from models.current_custody import CurrentCustodyInfo
from models.transfer_record import TransferRecord
from models.activity_log import ActivityLog
from services.custody_service import CustodyService


def create_test_db():
    engine = create_engine("sqlite:///:memory:", echo=False)
    Base.metadata.create_all(
        engine,
        tables=[
            CustodyLog.__table__,
            CurrentCustodyInfo.__table__,
            TransferRecord.__table__,
            ActivityLog.__table__
        ]
    )
    Session = sessionmaker(bind=engine)
    return Session()


def test_custody_transfer_lifecycle():
    """
    Test custody transfer:
    - Initial custody is null (no invented defaults)
    - Initiation generates unique reference and marks PENDING_RECEIPT
    - Contradictory transfer rejected while pending
    - Recipient mismatch rejected
    - Receipt confirms completion and updates holder without local hashing
    - Duplicate receipt rejected
    """
    db_session = create_test_db()
    try:
        evidence_id = "EV-TRF-001"
        case_id = "CASE-101"

        # 1. Initial check: holder and status are null
        curr_init = CustodyService.get_current_custody(db_session, evidence_id, case_id)
        assert curr_init["current_holder_name"] is None
        assert curr_init["custody_status"] is None

        # 2. Initiate transfer
        trf_res = CustodyService.initiate_transfer(
            db=db_session,
            evidence_id=evidence_id,
            sender_name="Inspector Rahul Singh",
            recipient_name="Jane Doe",
            remarks="Sent for forensic extraction",
            case_id=case_id
        )
        assert trf_res["status"] == "PENDING_RECEIPT"
        ref = trf_res["transfer_reference"]
        assert ref.startswith("TRF-")

        # Holder must NOT change upon initiation
        curr_mid = CustodyService.get_current_custody(db_session, evidence_id, case_id)
        assert curr_mid["current_holder_name"] is None
        assert curr_mid["custody_status"] == "PENDING_RECEIPT"
        assert curr_mid["pending_recipient_name"] == "Jane Doe"

        # 3. Contradictory transfer rejected
        caught = False
        try:
            CustodyService.initiate_transfer(
                db=db_session,
                evidence_id=evidence_id,
                sender_name="Inspector Rahul Singh",
                recipient_name="Third Party",
                case_id=case_id
            )
        except ValueError as e:
            assert "already has a pending transfer" in str(e)
            caught = True
        assert caught

        # 4. Recipient mismatch rejected
        caught = False
        try:
            CustodyService.receive_transfer(
                db=db_session,
                transfer_reference=ref,
                recipient_name="Wrong Person"
            )
        except ValueError as e:
            assert "Recipient mismatch" in str(e)
            caught = True
        assert caught

        # 5. Valid receipt confirmed
        recv_res = CustodyService.receive_transfer(
            db=db_session,
            transfer_reference=ref,
            recipient_name="Jane Doe",
            department="Cyber Cell, Mumbai",
            location="Digital Evidence Lab",
            remarks="Evidence received in sealed condition"
        )
        assert recv_res["status"] == "COMPLETED"

        # Now holder officially changes!
        curr_end = CustodyService.get_current_custody(db_session, evidence_id, case_id)
        assert curr_end["current_holder_name"] == "Jane Doe"
        assert curr_end["department"] == "Cyber Cell, Mumbai"
        assert curr_end["location"] == "Digital Evidence Lab"
        assert curr_end["custody_status"] == "In Analysis"
        assert curr_end["pending_recipient_name"] is None

        # 6. Duplicate receipt rejected
        caught = False
        try:
            CustodyService.receive_transfer(
                db=db_session,
                transfer_reference=ref,
                recipient_name="Jane Doe"
            )
        except ValueError as e:
            assert "already been completed" in str(e)
            caught = True
        assert caught
    finally:
        db_session.close()
    print("PASS: test_custody_transfer_lifecycle")


def test_current_custody_no_invented_defaults_and_audited_update():
    """
    Test that current custody starts null and rejects direct holder edit.
    """
    db_session = create_test_db()
    try:
        evidence_id = "EV-AUDIT-002"
        case_id = "CASE-102"

        curr = CustodyService.get_current_custody(db_session, evidence_id, case_id)
        assert curr["current_holder_name"] is None
        assert curr["custody_status"] is None

        # Update location and department
        updated = CustodyService.update_current_custody(
            db=db_session,
            evidence_id=evidence_id,
            department="Forensic HQ",
            location="Locker 4B",
            remarks="Secured in evidence locker",
            actor_name="Agent Smith"
        )
        assert updated["department"] == "Forensic HQ"
        assert updated["location"] == "Locker 4B"

        # Verify audit log was created
        logs = db_session.query(CustodyLog).filter(CustodyLog.evidence_id == evidence_id).all()
        assert len(logs) == 1
        assert logs[0].action == "CUSTODY_INFO_UPDATED"
        assert logs[0].event_type == "UPDATE"

        # Direct edit of holder MUST be rejected
        # First set a holder via transfer
        trf = CustodyService.initiate_transfer(
            db=db_session, evidence_id=evidence_id,
            sender_name="Sender", recipient_name="Holder A", case_id=case_id
        )
        CustodyService.receive_transfer(db=db_session, transfer_reference=trf["transfer_reference"], recipient_name="Holder A")

        # Now attempt direct edit
        caught = False
        try:
            CustodyService.update_current_custody(
                db=db_session,
                evidence_id=evidence_id,
                department="New Dept",
                actor_name="Agent Smith",
                new_holder_name="Different Person"
            )
        except ValueError as e:
            assert "Holder changes cannot be performed via direct edit" in str(e)
            caught = True
        assert caught
    finally:
        db_session.close()
    print("PASS: test_current_custody_no_invented_defaults_and_audited_update")


def test_access_event_no_holder_assignment():
    """
    Viewing/accessing evidence updates last_accessed and sets status to 'In Analysis',
    but must NOT automatically assign or alter the holder.
    """
    db_session = create_test_db()
    try:
        evidence_id = "EV-ACCESS-003"
        case_id = "CASE-103"

        res = CustodyService.record_access_event(
            db=db_session,
            evidence_id=evidence_id,
            actor_name="Cyber Analyst",
            actor_role="Cyber Expert",
            purpose="Integrity examination",
            case_id=case_id
        )
        assert res["status"] == "success"

        curr = CustodyService.get_current_custody(db_session, evidence_id, case_id)
        assert curr["current_holder_name"] is None  # Remains unassigned!
        assert curr["custody_status"] == "In Analysis"
        assert curr["last_accessed"] is not None
    finally:
        db_session.close()
    print("PASS: test_access_event_no_holder_assignment")


def test_external_custody_event_idempotency():
    """
    Ensure duplicate ingestion attempts with the same external_event_id
    do not produce duplicate records.
    """
    db_session = create_test_db()
    try:
        evidence_id = "EV-IDEMP-004"
        case_id = "CASE-104"
        ext_id = "EXT-LOG-12345"

        log1 = CustodyService.create_log(
            db=db_session,
            evidence_id=evidence_id,
            investigator_name="Investigator A",
            action="EVIDENCE_UPLOADED",
            case_id=case_id,
            external_event_id=ext_id,
            timestamp=datetime.now(timezone.utc)
        )
        assert log1 is not None

        log2 = CustodyService.create_log(
            db=db_session,
            evidence_id=evidence_id,
            investigator_name="Investigator A",
            action="EVIDENCE_UPLOADED",
            case_id=case_id,
            external_event_id=ext_id,
            timestamp=datetime.now(timezone.utc)
        )
        assert log2.id == log1.id

        count = db_session.query(CustodyLog).filter(CustodyLog.external_event_id == ext_id).count()
        assert count == 1
    finally:
        db_session.close()
    print("PASS: test_external_custody_event_idempotency")


def test_timeline_reconstruction_and_deduplication():
    """
    Test TimelineService:
    - Multiple audit logs sharing the same event_reference are merged into one timeline item.
    - True timestamps and deterministic sorting.
    """
    from services.timeline_service import TimelineService
    from uuid import uuid4

    db_session = create_test_db()
    try:
        case_id = "CASE-TL-55"
        ev_id = "EV-55"
        event_ref = str(uuid4())
        dt = datetime.now(timezone.utc)

        # 1. Custody log
        cl = CustodyLog(
            evidence_id=ev_id,
            case_id=case_id,
            action="TRANSFER_INITIATED",
            event_type="TRANSFER",
            investigator_name="Agent A",
            event_reference=event_ref,
            timestamp=dt,
            remarks="Dispatched"
        )
        db_session.add(cl)

        # 2. Activity log sharing same event_reference
        al = ActivityLog(
            case_id=case_id,
            external_evidence_id=ev_id,
            action="TRANSFER_INITIATED",
            investigator_name="Agent A",
            activity="Transfer initiated",
            event_reference=event_ref,
            timestamp=dt,
            details="Dispatched"
        )
        db_session.add(al)
        db_session.commit()

        # Build case timeline
        tl = TimelineService.build_case_timeline(db_session, case_id)
        # Should be deduplicated into 1 step!
        assert len(tl) == 1
        assert tl[0]["step"] == 1
        assert tl[0]["event_type"] == "TRANSFER_INITIATED"
        assert tl[0]["event_reference"] == event_ref
        assert "AUDIT_TRAIL" in tl[0]["source"]
    finally:
        db_session.close()
    print("PASS: test_timeline_reconstruction_and_deduplication")


if __name__ == "__main__":
    print("\n========================================================")
    print("RUNNING DEEPAK CHAIN OF CUSTODY UNIT TESTS")
    print("========================================================")
    test_custody_transfer_lifecycle()
    test_current_custody_no_invented_defaults_and_audited_update()
    test_access_event_no_holder_assignment()
    test_external_custody_event_idempotency()
    test_timeline_reconstruction_and_deduplication()
    print("ALL DEEPAK CORE CUSTODY UNIT TESTS PASSED SUCCESSFULLY!\n")
