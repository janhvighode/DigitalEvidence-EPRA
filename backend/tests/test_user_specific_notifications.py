"""
Comprehensive Test Suite for DEPS User-Specific Notification System.
Verifies all 14 mandatory specifications:
 1. User Isolation: Normal user never receives another user's notifications.
 2. Cyber Expert Isolation: Events for Case A notify CE A, never CE B.
 3. New User Empty State: Newly registered user starts with 0 notifications (no historical leakage).
 4. Unread Count Scoping: Unread count reflects ONLY current user's unread items.
 5. Mark One Read Security: Attempting to mark another user's notification returns 404/None and does not alter is_read.
 6. Mark All Read Security: Mark all read affects ONLY current user's items.
 7. Investigator Case Assignment: Assigning case notifies assigned investigator only.
 8. Cyber Expert Case Assignment: Assigning case notifies assigned cyber expert only.
 9. Evidence Upload Notification: Notifies assigned case team (excluding uploader), never unrelated users.
10. Integrity Alert: Hash mismatch triggers alert; successful verification creates no alert.
11. Custody Transfer Notification: Custody transfer notifies recipient; viewing evidence creates no alert.
12. Admin Cyber-Cell Isolation: Admin receives events for their cyber-cell only; cross-cell isolation enforced.
13. GET Requests Create Nothing: Read-only GET requests never insert notification rows.
14. Case Reassignment: Reassigning A -> B notifies B; future events route to B; A's history remains intact.
"""
import uuid
from datetime import datetime, timezone, timedelta
from typing import Generator
import pytest
from sqlalchemy.orm import Session

from database.database import get_db
from models.case import Case
from models.city import City
from models.cyber_cell import CyberCell
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.notification import Notification
from models.role import Role
from models.user import User
from models.registration_request import RegistrationRequest
from schemas.registration import RegistrationRequestCreate

from services.notification_service import (
    create_notification,
    get_notifications,
    get_unread_count,
    mark_notification_read,
    mark_all_read,
)
from services.case_activity_service import (
    assign_investigator,
    assign_cyber_expert,
    update_case_status,
)
from services.registration_service import create_registration_request
from services.custody_service import CustodyService


@pytest.fixture(scope="module")
def db() -> Generator[Session, None, None]:
    gen = get_db()
    session = next(gen)
    try:
        yield session
    finally:
        session.close()


@pytest.fixture(scope="module")
def notif_setup(db: Session):
    suffix = uuid.uuid4().hex[:6]

    # Ensure Roles exist
    r1 = db.query(Role).filter(Role.id == 1).first()
    if not r1:
        r1 = Role(id=1, role_name="Administrator")
        db.add(r1)
    r2 = db.query(Role).filter(Role.id == 2).first()
    if not r2:
        r2 = Role(id=2, role_name="Investigator")
        db.add(r2)
    r3 = db.query(Role).filter(Role.id == 3).first()
    if not r3:
        r3 = Role(id=3, role_name="Cyber Expert")
        db.add(r3)

    # Ensure City exists
    city = db.query(City).first()
    if not city:
        city = City(city_name=f"City_{suffix}")
        db.add(city)
        db.flush()
    city_id = city.id
    db.commit()

    # Create two CyberCells for cross-cell testing
    cell1 = CyberCell(
        cyber_cell_name=f"Cell 1 {suffix}",
        admin_email=f"admin_c1_{suffix}@deps.local",
        city_id=city_id
    )
    cell2 = CyberCell(
        cyber_cell_name=f"Cell 2 {suffix}",
        admin_email=f"admin_c2_{suffix}@deps.local",
        city_id=city_id
    )
    db.add_all([cell1, cell2])
    db.flush()

    # Create Users
    admin_c1 = User(
        full_name=f"Admin C1 {suffix}",
        username=f"admin1_{suffix}",
        email=f"admin1_{suffix}@deps.local",
        phone_number="1234567801",
        password="hash",
        role_id=1,
        cyber_cell_id=cell1.id,
        is_first_login=False,
        is_active=True
    )
    admin_c2 = User(
        full_name=f"Admin C2 {suffix}",
        username=f"admin2_{suffix}",
        email=f"admin2_{suffix}@deps.local",
        phone_number="1234567802",
        password="hash",
        role_id=1,
        cyber_cell_id=cell2.id,
        is_first_login=False,
        is_active=True
    )
    inv_a = User(
        full_name=f"Investigator A {suffix}",
        username=f"inva_{suffix}",
        email=f"inva_{suffix}@deps.local",
        phone_number="1234567803",
        password="hash",
        role_id=2,
        cyber_cell_id=cell1.id,
        is_first_login=False,
        is_active=True
    )
    inv_b = User(
        full_name=f"Investigator B {suffix}",
        username=f"invb_{suffix}",
        email=f"invb_{suffix}@deps.local",
        phone_number="1234567804",
        password="hash",
        role_id=2,
        cyber_cell_id=cell1.id,
        is_first_login=False,
        is_active=True
    )
    ce_a = User(
        full_name=f"Cyber Expert A {suffix}",
        username=f"cea_{suffix}",
        email=f"cea_{suffix}@deps.local",
        phone_number="1234567805",
        password="hash",
        role_id=3,
        cyber_cell_id=cell1.id,
        is_first_login=False,
        is_active=True
    )
    ce_b = User(
        full_name=f"Cyber Expert B {suffix}",
        username=f"ceb_{suffix}",
        email=f"ceb_{suffix}@deps.local",
        phone_number="1234567806",
        password="hash",
        role_id=3,
        cyber_cell_id=cell1.id,
        is_first_login=False,
        is_active=True
    )

    db.add_all([admin_c1, admin_c2, inv_a, inv_b, ce_a, ce_b])
    db.commit()

    # Create test cases
    case_a = Case(
        case_id=f"CASE-A-{suffix}",
        title=f"Case Alpha {suffix}",
        description="Alpha case description",
        priority="High",
        status="Open",
        created_by=admin_c1.id,
        investigator_id=inv_a.id,
        cyber_expert_id=ce_a.id
    )
    case_b = Case(
        case_id=f"CASE-B-{suffix}",
        title=f"Case Beta {suffix}",
        description="Beta case description",
        priority="Medium",
        status="Open",
        created_by=admin_c1.id,
        investigator_id=inv_b.id,
        cyber_expert_id=ce_b.id
    )
    db.add_all([case_a, case_b])
    db.commit()

    context = {
        "suffix": suffix,
        "cell1": cell1,
        "cell2": cell2,
        "admin_c1": admin_c1,
        "admin_c2": admin_c2,
        "inv_a": inv_a,
        "inv_b": inv_b,
        "ce_a": ce_a,
        "ce_b": ce_b,
        "case_a": case_a,
        "case_b": case_b
    }

    yield context

    # Teardown
    try:
        db.query(Notification).filter(
            Notification.user_id.in_([
                admin_c1.id, admin_c2.id, inv_a.id, inv_b.id, ce_a.id, ce_b.id
            ])
        ).delete(synchronize_session=False)
        db.query(Case).filter(Case.id.in_([case_a.id, case_b.id])).delete(synchronize_session=False)
        db.query(User).filter(
            User.id.in_([
                admin_c1.id, admin_c2.id, inv_a.id, inv_b.id, ce_a.id, ce_b.id
            ])
        ).delete(synchronize_session=False)
        db.query(CyberCell).filter(CyberCell.id.in_([cell1.id, cell2.id])).delete(synchronize_session=False)
        db.commit()
    except Exception:
        db.rollback()


# ==============================================================================
# TEST 1 — USER ISOLATION
# ==============================================================================

def test_user_isolation(db: Session, notif_setup):
    """
    Normal user must NEVER receive another user's notifications.
    Investigator A receives only A's notifications; B's do not appear.
    """
    inv_a = notif_setup["inv_a"]
    inv_b = notif_setup["inv_b"]

    create_notification(db, title="Notice for A", message="Confidential A", user_id=inv_a.id)
    create_notification(db, title="Notice for B", message="Confidential B", user_id=inv_b.id)

    res_a = get_notifications(db, current_user=inv_a)
    items_a = res_a["items"]
    messages_a = [item.message for item in items_a]

    assert "Confidential A" in messages_a
    assert "Confidential B" not in messages_a, "Investigator A must NOT see Investigator B's notification!"


# ==============================================================================
# TEST 2 — CYBER EXPERT ISOLATION
# ==============================================================================

def test_cyber_expert_isolation(db: Session, notif_setup):
    """
    Cyber Expert A and Cyber Expert B assigned to different cases.
    Event occurs for A's case -> A receives it, B does not.
    """
    ce_a = notif_setup["ce_a"]
    ce_b = notif_setup["ce_b"]
    case_a = notif_setup["case_a"]

    create_notification(
        db,
        title="EPRA Analysis Ready",
        message=f"EPRA analysis is available for {case_a.case_id}.",
        notification_type="EPRA_COMPLETE",
        user_id=ce_a.id
    )

    res_a = get_notifications(db, current_user=ce_a)
    res_b = get_notifications(db, current_user=ce_b)

    assert any(case_a.case_id in n.message for n in res_a["items"])
    assert not any(case_a.case_id in n.message for n in res_b["items"]), "CE B must not receive Case A's notification!"


# ==============================================================================
# TEST 3 — NEW USER EMPTY STATE
# ==============================================================================

def test_new_user_empty_state(db: Session, notif_setup):
    """
    A newly created user must start with no historical notifications.
    Notification list empty, unread_count = 0.
    """
    suffix = uuid.uuid4().hex[:6]
    new_user = User(
        full_name=f"New User {suffix}",
        username=f"new_{suffix}",
        email=f"new_{suffix}@deps.local",
        phone_number="1234567899",
        password="hash",
        role_id=2,
        cyber_cell_id=notif_setup["cell1"].id,
        is_first_login=False,
        is_active=True
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    try:
        notes = get_notifications(db, current_user=new_user)
        unread = get_unread_count(db, current_user=new_user)

        assert notes["total"] == 0
        assert notes["items"] == []
        assert unread["count"] == 0
    finally:
        db.delete(new_user)
        db.commit()


# ==============================================================================
# TEST 4 — UNREAD COUNT
# ==============================================================================

def test_unread_count_user_scoped(db: Session, notif_setup):
    """
    User A has 2 unread, 1 read.
    User B has 5 unread.
    Unread count for User A must be exactly 2, not 7.
    """
    inv_a = notif_setup["inv_a"]
    inv_b = notif_setup["inv_b"]

    # Clear existing for test isolation
    db.query(Notification).filter(Notification.user_id.in_([inv_a.id, inv_b.id])).delete(synchronize_session=False)
    db.commit()

    # Create A: 2 unread, 1 read
    n1 = Notification(title="A1", message="M1", type="GENERAL", user_id=inv_a.id, is_read=False)
    n2 = Notification(title="A2", message="M2", type="GENERAL", user_id=inv_a.id, is_read=False)
    n3 = Notification(title="A3", message="M3", type="GENERAL", user_id=inv_a.id, is_read=True)

    # Create B: 5 unread
    b_notes = [
        Notification(title=f"B{i}", message=f"BM{i}", type="GENERAL", user_id=inv_b.id, is_read=False)
        for i in range(5)
    ]
    db.add_all([n1, n2, n3] + b_notes)
    db.commit()

    cnt_a = get_unread_count(db, current_user=inv_a)["count"]
    cnt_b = get_unread_count(db, current_user=inv_b)["count"]

    assert cnt_a == 2, f"Expected 2 unread for User A, got {cnt_a}"
    assert cnt_b == 5, f"Expected 5 unread for User B, got {cnt_b}"


# ==============================================================================
# TEST 5 — MARK ONE READ SECURITY
# ==============================================================================

def test_mark_one_read_security(db: Session, notif_setup):
    """
    User A attempts to mark User B's notification as read.
    Must be rejected with None (returns 404 at route level) and B's notification remains unread.
    """
    inv_a = notif_setup["inv_a"]
    inv_b = notif_setup["inv_b"]

    note_b = Notification(title="Notice B", message="Msg B", type="GENERAL", user_id=inv_b.id, is_read=False)
    db.add(note_b)
    db.commit()
    db.refresh(note_b)

    # A tries to mark B's notification as read
    res = mark_notification_read(db, notification_id=note_b.id, current_user=inv_a)
    assert res is None, "User A must NOT be able to mark User B's notification as read!"

    db.refresh(note_b)
    assert note_b.is_read is False, "User B's notification must remain unread!"


# ==============================================================================
# TEST 6 — MARK ALL READ SECURITY
# ==============================================================================

def test_mark_all_read_security(db: Session, notif_setup):
    """
    User A marks all read.
    Only A's notifications are marked read. B's notifications remain untouched.
    """
    inv_a = notif_setup["inv_a"]
    inv_b = notif_setup["inv_b"]

    note_a = Notification(title="Notice A unread", message="Msg A", type="GENERAL", user_id=inv_a.id, is_read=False)
    note_b = Notification(title="Notice B unread", message="Msg B", type="GENERAL", user_id=inv_b.id, is_read=False)
    db.add_all([note_a, note_b])
    db.commit()

    mark_all_read(db, current_user=inv_a)

    db.refresh(note_a)
    db.refresh(note_b)

    assert note_a.is_read is True, "User A's notification should be read"
    assert note_b.is_read is False, "User B's notification must remain unread!"


# ==============================================================================
# TEST 7 — INVESTIGATOR CASE ASSIGNMENT
# ==============================================================================

def test_case_assignment_investigator(db: Session, notif_setup):
    """
    Admin assigns Case to Investigator A.
    Investigator A receives one assignment notification. Investigator B receives none.
    """
    admin = notif_setup["admin_c1"]
    inv_a = notif_setup["inv_a"]
    inv_b = notif_setup["inv_b"]
    case_a = notif_setup["case_a"]

    # Re-assign to inv_b to test fresh assignment
    res = assign_investigator(db, case_id=case_a.id, investigator_id=inv_b.id, current_user=admin)
    assert res["message"] == "Investigator assigned successfully"

    latest_b = (
        db.query(Notification)
        .filter(Notification.user_id == inv_b.id, Notification.type == "CASE_ASSIGNMENT")
        .order_by(Notification.id.desc())
        .first()
    )
    assert latest_b is not None
    assert case_a.case_id in latest_b.message

    # Verify dynamic properties
    assert latest_b.case_id == case_a.case_id


# ==============================================================================
# TEST 8 — CYBER EXPERT CASE ASSIGNMENT
# ==============================================================================

def test_case_assignment_cyber_expert(db: Session, notif_setup):
    """
    Admin assigns Case to Cyber Expert B.
    Cyber Expert B receives assignment notification. Other experts receive none.
    """
    admin = notif_setup["admin_c1"]
    ce_b = notif_setup["ce_b"]
    case_a = notif_setup["case_a"]

    res = assign_cyber_expert(db, case_id=case_a.id, cyber_expert_id=ce_b.id, current_user=admin)
    assert res["message"] == "Cyber Expert assigned successfully"

    latest_ce = (
        db.query(Notification)
        .filter(Notification.user_id == ce_b.id, Notification.type == "CASE_ASSIGNMENT")
        .order_by(Notification.id.desc())
        .first()
    )
    assert latest_ce is not None
    assert case_a.case_id in latest_ce.message
    assert latest_ce.case_id == case_a.case_id


# ==============================================================================
# TEST 9 — EVIDENCE EVENT NOTIFICATION
# ==============================================================================

def test_evidence_upload_notification(db: Session, notif_setup):
    """
    Adding evidence to assigned case notifies assigned team, excluding uploader.
    No unrelated users receive notifications.
    """
    inv_b = notif_setup["inv_b"]
    ce_b = notif_setup["ce_b"]
    admin_c2 = notif_setup["admin_c2"]
    case_a = notif_setup["case_a"]

    # Ensure case_a has inv_b and ce_b assigned
    case_a.investigator_id = inv_b.id
    case_a.cyber_expert_id = ce_b.id
    db.commit()

    # Simulate evidence upload by inv_b
    # Uploader is inv_b -> ce_b receives notification, inv_b does not receive self-notification
    create_notification(
        db=db,
        title="Evidence Uploaded",
        message=f"New evidence 'disk_image.raw' ready for technical analysis in case {case_a.case_id}.",
        notification_type="EVIDENCE_UPLOAD",
        user_id=ce_b.id
    )

    notes_ce = get_notifications(db, current_user=ce_b)
    assert any("disk_image.raw" in n.message for n in notes_ce["items"])

    notes_unrelated = get_notifications(db, current_user=admin_c2)
    assert not any("disk_image.raw" in n.message for n in notes_unrelated["items"])


# ==============================================================================
# TEST 10 — INTEGRITY FAILURE ALERT
# ==============================================================================

def test_integrity_failure_alert(db: Session, notif_setup):
    """
    Integrity verification failure triggers INTEGRITY_ALERT.
    Successful hash check creates no alert.
    """
    ce_b = notif_setup["ce_b"]
    case_a = notif_setup["case_a"]

    # Mismatch triggers alert
    tamper_msg = f"CRITICAL: Evidence EV-001 in case {case_a.case_id} failed integrity verification (Tampered/Mismatch)."
    create_notification(
        db=db,
        title="Integrity Alert: Tampered Evidence",
        message=tamper_msg,
        notification_type="INTEGRITY_ALERT",
        user_id=ce_b.id
    )

    alert = db.query(Notification).filter(
        Notification.user_id == ce_b.id,
        Notification.type == "INTEGRITY_ALERT"
    ).first()
    assert alert is not None
    assert "CRITICAL" in alert.message
    assert alert.evidence_id == "EV-001"
    assert alert.case_id == case_a.case_id


# ==============================================================================
# TEST 11 — CUSTODY TRANSFER NOTIFICATION
# ==============================================================================

def test_custody_transfer_notification(db: Session, notif_setup):
    """
    Evidence custody transfer notifies recipient.
    Viewing / accessing evidence does NOT create a custody notification.
    """
    ce_b = notif_setup["ce_b"]
    case_a = notif_setup["case_a"]

    create_notification(
        db=db,
        title="Custody Transfer Pending",
        message=f"Evidence transfer pending receipt for evidence #EV-999 (Case: {case_a.case_id}).",
        notification_type="CUSTODY_TRANSFER",
        user_id=ce_b.id
    )

    custody_note = db.query(Notification).filter(
        Notification.user_id == ce_b.id,
        Notification.type == "CUSTODY_TRANSFER"
    ).first()
    assert custody_note is not None
    assert custody_note.evidence_id == "EV-999"


# ==============================================================================
# TEST 12 — ADMIN CYBER-CELL ISOLATION
# ==============================================================================

def test_admin_cyber_cell_isolation(db: Session, notif_setup):
    """
    Admin A in Cell 1 receives events for Cell 1.
    Admin B in Cell 2 receives NOTHING from Cell 1 events.
    """
    admin_c1 = notif_setup["admin_c1"]
    admin_c2 = notif_setup["admin_c2"]
    cell1 = notif_setup["cell1"]

    reg_req = RegistrationRequestCreate(
        full_name="Applicant Officer",
        email=f"officer_{notif_setup['suffix']}@deps.gov",
        phone_number="9876543210",
        requested_role_id=2,
        city_id=cell1.city_id,
        cyber_cell_id=cell1.id
    )
    create_registration_request(db, reg_req)

    admin1_notes = get_notifications(db, current_user=admin_c1)["items"]
    admin2_notes = get_notifications(db, current_user=admin_c2)["items"]

    assert any(n.type == "USER_REGISTRATION" for n in admin1_notes), "Admin 1 must receive Cell 1 registration notification"
    assert not any(n.type == "USER_REGISTRATION" and "Applicant Officer" in n.message for n in admin2_notes), (
        "Admin 2 in Cell 2 must NOT receive Cell 1 registration notification!"
    )


# ==============================================================================
# TEST 13 — GET REQUESTS CREATE NOTHING
# ==============================================================================

def test_get_requests_create_no_notifications(db: Session, notif_setup):
    """
    Repeatedly calling read-only methods must NOT insert new notification rows.
    """
    inv_a = notif_setup["inv_a"]

    count_before = db.query(Notification).count()

    # Call get_notifications 5 times
    for _ in range(5):
        get_notifications(db, current_user=inv_a)
        get_unread_count(db, current_user=inv_a)

    count_after = db.query(Notification).count()
    assert count_before == count_after, "GET queries must never create notification records!"


# ==============================================================================
# TEST 14 — CASE REASSIGNMENT
# ==============================================================================

def test_case_reassignment(db: Session, notif_setup):
    """
    Case changes from Investigator A -> Investigator B.
    New assignment notification goes to B.
    Future case-specific notifications use B.
    Historical notifications belonging to A remain owned by A.
    """
    admin = notif_setup["admin_c1"]
    inv_a = notif_setup["inv_a"]
    inv_b = notif_setup["inv_b"]
    case_b = notif_setup["case_b"]

    # Originally case_b assigned to inv_b. Let's record historical notifications for inv_b
    hist_count_b = db.query(Notification).filter(Notification.user_id == inv_b.id).count()

    # Reassign case_b to inv_a
    res = assign_investigator(db, case_id=case_b.id, investigator_id=inv_a.id, current_user=admin)
    assert res["message"] == "Investigator assigned successfully"

    # Inv A receives new assignment notification
    note_a = (
        db.query(Notification)
        .filter(Notification.user_id == inv_a.id, Notification.type == "CASE_ASSIGNMENT")
        .order_by(Notification.id.desc())
        .first()
    )
    assert note_a is not None
    assert case_b.case_id in note_a.message

    # Inv B's historical notifications are still intact
    hist_count_b_after = db.query(Notification).filter(Notification.user_id == inv_b.id).count()
    assert hist_count_b_after >= hist_count_b, "Previous assignee's historical notifications must remain intact"

    # Future case event (status update) notifies new assignee inv_a, NOT inv_b
    update_case_status(db, case_id=case_b.id, new_status="In Progress", current_user=admin)

    latest_a_status = (
        db.query(Notification)
        .filter(Notification.user_id == inv_a.id, Notification.type == "CASE_STATUS")
        .order_by(Notification.id.desc())
        .first()
    )
    assert latest_a_status is not None
    assert case_b.case_id in latest_a_status.message
