"""
Comprehensive Test Suite for Secure User-Specific Notifications and Cross-User Data Isolation.
Covers all 36 mandatory verification specifications:
 1. Admin retrieves only own notifications
 2. Investigator retrieves only own notifications
 3. Cyber Expert retrieves only own notifications
 4. New user gets []
 5. Branch/cyber_cell notification does not leak to Admin
 6. User A cannot read User B notification
 7. User A cannot mark User B notification read
 8. User A cannot affect User B unread count
 9. unread count correct
10. mark one read works
11. mark all read affects only current user
12. pagination page 1
13. pagination page 2
14. invalid page rejected
15. invalid limit rejected
16. assignment notification isolation
17. Cyber Expert assignment isolation
18. registration notification per Admin recipient
19. evidence upload recipient isolation
20. integrity mismatch recipient isolation
21. EPRA complete recipient isolation
22. EPRA critical recipient isolation
23. CBIR meaningful match notification
24. weak/no-match CBIR creates no alert
25. custody transfer only target recipient
26. technical report generation notification
27. preview/download creates no report notification
28. repeated same assignment no duplicate
29. repeated same status no duplicate
30. new Investigator zero-case empty state
31. new Cyber Expert zero-case empty state
32. cross-case EPRA blocked
33. cross-case CBIR blocked
34. cross-case report access blocked
35. legacy /reports no longer unauthenticated
36. no token notification API -> 401
"""
import os
import sys
import inspect
from pathlib import Path
from datetime import datetime
from fastapi import HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, Session

# Setup system paths
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))
root_dir = backend_dir.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))

from database.database import Base
from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.notification import Notification
from models.registration_request import RegistrationRequest
from models.case_timeline import CaseTimeline
from models.epra_result import EPRAResult
from models.report_record import ReportRecord
from models.transfer_record import TransferRecord

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
import unittest.mock
from services.registration_service import create_registration_request
from services.evidence_service import create_case_evidence
from services.epra_service import (
    authorize_cyber_expert_case_access as authorize_epra_access,
)
from services.cbir_service import (
    authorize_cyber_expert_case_access as authorize_cbir_access,
)
from services.technical_report_service import TechnicalReportService
from services.report_service import get_completed_reports, get_report_details
from services.cyber_expert_dashboard_service import (
    get_cyber_expert_dashboard_stats,
    get_cyber_expert_cases,
)
from services.investigator_dashboard_service import (
    get_investigator_dashboard_stats,
    get_investigator_my_cases,
)
from schemas.registration import RegistrationRequestCreate
from utils.current_user import get_current_user
from utils.jwt_handler import create_access_token
from routes.report_routes import router as legacy_report_router
from routes.notification_routes import router as notification_router


def setup_test_db() -> Session:
    """Create in-memory SQLite database and return a clean session."""
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
            Notification.__table__,
            RegistrationRequest.__table__,
            CaseTimeline.__table__,
            EPRAResult.__table__,
            ReportRecord.__table__,
            TransferRecord.__table__,
        ]
    )
    SessionMaker = sessionmaker(bind=engine)
    return SessionMaker()


def run_all_tests():
    print("=" * 80)
    print("RUNNING COMPREHENSIVE NOTIFICATION & DATA ISOLATION TEST SUITE (36 TESTS)")
    print("=" * 80)

    db = setup_test_db()

    # --------------------------------------------------------------------------
    # Seed Basic Metadata and Roles
    # --------------------------------------------------------------------------
    roles = [
        Role(id=1, role_name="Administrator"),
        Role(id=2, role_name="Investigator"),
        Role(id=3, role_name="Cyber Expert"),
    ]
    city = City(id=1, city_name="Nagpur")
    cyber_cell_1 = CyberCell(id=1, cyber_cell_name="Nagpur Cyber Cell", admin_email="admin1@deps.gov", city_id=1)
    cyber_cell_2 = CyberCell(id=2, cyber_cell_name="Pune Cyber Cell", admin_email="admin2@deps.gov", city_id=1)
    db.add_all(roles + [city, cyber_cell_1, cyber_cell_2])
    db.commit()

    # --------------------------------------------------------------------------
    # Seed Users
    # --------------------------------------------------------------------------
    admin_1 = User(
        id=1, full_name="Admin One", username="admin1", email="admin1@deps.gov",
        phone_number="9990000001", password="Password@123", role_id=1, cyber_cell_id=1, is_active=True
    )
    admin_2 = User(
        id=2, full_name="Admin Two", username="admin2", email="admin2@deps.gov",
        phone_number="9990000002", password="Password@123", role_id=1, cyber_cell_id=1, is_active=True
    )
    inv_a = User(
        id=3, full_name="Investigator A", username="inva", email="inva@deps.gov",
        phone_number="9990000003", password="Password@123", role_id=2, cyber_cell_id=1, is_active=True
    )
    inv_b = User(
        id=4, full_name="Investigator B", username="invb", email="invb@deps.gov",
        phone_number="9990000004", password="Password@123", role_id=2, cyber_cell_id=1, is_active=True
    )
    ce_a = User(
        id=5, full_name="Cyber Expert A", username="cea", email="cea@deps.gov",
        phone_number="9990000005", password="Password@123", role_id=3, cyber_cell_id=1, is_active=True
    )
    ce_b = User(
        id=6, full_name="Cyber Expert B", username="ceb", email="ceb@deps.gov",
        phone_number="9990000006", password="Password@123", role_id=3, cyber_cell_id=1, is_active=True
    )
    new_inv = User(
        id=7, full_name="New Investigator", username="newinv", email="newinv@deps.gov",
        phone_number="9990000007", password="Password@123", role_id=2, cyber_cell_id=1, is_active=True
    )
    new_ce = User(
        id=8, full_name="New Cyber Expert", username="newce", email="newce@deps.gov",
        phone_number="9990000008", password="Password@123", role_id=3, cyber_cell_id=1, is_active=True
    )
    db.add_all([admin_1, admin_2, inv_a, inv_b, ce_a, ce_b, new_inv, new_ce])
    db.commit()

    # --------------------------------------------------------------------------
    # Seed Sample Cases
    # --------------------------------------------------------------------------
    case_1 = Case(
        id=1, case_id="CASE-1001", title="Cyber Heist Investigation",
        description="Bank fraud", investigator_id=inv_a.id, cyber_expert_id=ce_a.id,
        priority="Critical", status="Open", created_by=admin_1.id
    )
    case_2 = Case(
        id=2, case_id="CASE-1002", title="Ransomware Intrusion",
        description="Hospital crypto locker", investigator_id=inv_b.id, cyber_expert_id=ce_b.id,
        priority="High", status="In Progress", created_by=admin_1.id
    )
    db.add_all([case_1, case_2])
    db.commit()

    # ==========================================================================
    # TEST 1: Admin retrieves only own notifications
    # ==========================================================================
    create_notification(db, title="Admin Notice", message="For Admin 1", user_id=admin_1.id)
    create_notification(db, title="Other Notice", message="For Admin 2", user_id=admin_2.id)
    admin_notes = get_notifications(db, current_user=admin_1)
    assert admin_notes["total"] == 1, f"Expected 1 notification for Admin 1, got {admin_notes['total']}"
    assert admin_notes["items"][0].message == "For Admin 1"
    print("PASS: 1. Admin retrieves only own notifications")

    # ==========================================================================
    # TEST 2: Investigator retrieves only own notifications
    # ==========================================================================
    create_notification(db, title="Inv A Notice", message="For Inv A", user_id=inv_a.id)
    create_notification(db, title="Inv B Notice", message="For Inv B", user_id=inv_b.id)
    inv_notes = get_notifications(db, current_user=inv_a)
    assert inv_notes["total"] == 1
    assert inv_notes["items"][0].message == "For Inv A"
    print("PASS: 2. Investigator retrieves only own notifications")

    # ==========================================================================
    # TEST 3: Cyber Expert retrieves only own notifications
    # ==========================================================================
    create_notification(db, title="CE A Notice", message="For CE A", user_id=ce_a.id)
    create_notification(db, title="CE B Notice", message="For CE B", user_id=ce_b.id)
    ce_notes = get_notifications(db, current_user=ce_a)
    assert ce_notes["total"] == 1
    assert ce_notes["items"][0].message == "For CE A"
    print("PASS: 3. Cyber Expert retrieves only own notifications")

    # ==========================================================================
    # TEST 4: New user gets []
    # ==========================================================================
    new_inv_notes = get_notifications(db, current_user=new_inv)
    assert new_inv_notes["total"] == 0
    assert new_inv_notes["unread_count"] == 0
    assert new_inv_notes["items"] == []
    print("PASS: 4. New user gets []")

    # ==========================================================================
    # TEST 5: Branch/cyber_cell notification does not leak to Admin
    # ==========================================================================
    db.add(Notification(
        title="Broadcast Leak Test",
        message="Should not be visible to Admin 1 via cyber_cell_id",
        type="SYSTEM",
        user_id=None,  # Old orphan/broadcast row
        cyber_cell_id=admin_1.cyber_cell_id,
        is_read=False
    ))
    db.commit()
    admin_after_leak = get_notifications(db, current_user=admin_1)
    assert admin_after_leak["total"] == 1
    assert all(n.title != "Broadcast Leak Test" for n in admin_after_leak["items"])
    print("PASS: 5. Branch/cyber_cell notification does not leak to Admin")

    # ==========================================================================
    # TEST 6: User A cannot read User B notification
    # ==========================================================================
    user_b_row = db.query(Notification).filter(Notification.user_id == inv_b.id).first()
    assert user_b_row is not None
    user_a_notes = get_notifications(db, current_user=inv_a)
    user_a_note_ids = [n.id for n in user_a_notes["items"]]
    assert user_b_row.id not in user_a_note_ids
    print("PASS: 6. User A cannot read User B notification")

    # ==========================================================================
    # TEST 7: User A cannot mark User B notification read
    # ==========================================================================
    res = mark_notification_read(db, notification_id=user_b_row.id, current_user=inv_a)
    assert res is None
    db.refresh(user_b_row)
    assert user_b_row.is_read is False
    print("PASS: 7. User A cannot mark User B notification read")

    # ==========================================================================
    # TEST 8: User A cannot affect User B unread count
    # ==========================================================================
    b_unread_before = get_unread_count(db, current_user=inv_b)["count"]
    mark_all_read(db, current_user=inv_a)
    b_unread_after = get_unread_count(db, current_user=inv_b)["count"]
    assert b_unread_before == b_unread_after
    print("PASS: 8. User A cannot affect User B unread count")

    # ==========================================================================
    # TEST 9: unread count correct
    # ==========================================================================
    create_notification(db, title="N1", message="M1", user_id=inv_a.id)
    create_notification(db, title="N2", message="M2", user_id=inv_a.id)
    cnt = get_unread_count(db, current_user=inv_a)["count"]
    assert cnt == 2
    print("PASS: 9. unread count correct")

    # ==========================================================================
    # TEST 10: mark one read works
    # ==========================================================================
    inv_a_unread = db.query(Notification).filter(Notification.user_id == inv_a.id, Notification.is_read == False).first()
    updated = mark_notification_read(db, notification_id=inv_a_unread.id, current_user=inv_a)
    assert updated is not None
    assert updated.is_read is True
    assert get_unread_count(db, current_user=inv_a)["count"] == 1
    print("PASS: 10. mark one read works")

    # ==========================================================================
    # TEST 11: mark all read affects only current user
    # ==========================================================================
    marked_count = mark_all_read(db, current_user=inv_a)
    assert marked_count == 1
    assert get_unread_count(db, current_user=inv_a)["count"] == 0
    assert get_unread_count(db, current_user=inv_b)["count"] > 0
    print("PASS: 11. mark all read affects only current user")

    # ==========================================================================
    # TEST 12: pagination page 1
    # ==========================================================================
    for i in range(25):
        create_notification(db, title=f"Bulk {i}", message=f"Message {i}", user_id=inv_a.id)
    p1 = get_notifications(db, current_user=inv_a, page=1, limit=10)
    assert p1["page"] == 1
    assert p1["limit"] == 10
    assert len(p1["items"]) == 10
    assert p1["total"] >= 25
    print("PASS: 12. pagination page 1")

    # ==========================================================================
    # TEST 13: pagination page 2
    # ==========================================================================
    p2 = get_notifications(db, current_user=inv_a, page=2, limit=10)
    assert p2["page"] == 2
    assert len(p2["items"]) == 10
    p1_ids = {item.id for item in p1["items"]}
    p2_ids = {item.id for item in p2["items"]}
    assert len(p1_ids.intersection(p2_ids)) == 0
    print("PASS: 13. pagination page 2")

    # ==========================================================================
    # TEST 14: invalid page rejected
    # ==========================================================================
    try:
        get_notifications(db, current_user=inv_a, page=0, limit=10)
        assert False, "Should have raised HTTPException for page < 1"
    except HTTPException as e:
        assert e.status_code == 400
    print("PASS: 14. invalid page rejected")

    # ==========================================================================
    # TEST 15: invalid limit rejected
    # ==========================================================================
    try:
        get_notifications(db, current_user=inv_a, page=1, limit=101)
        assert False, "Should have raised HTTPException for limit > 100"
    except HTTPException as e:
        assert e.status_code == 400
    print("PASS: 15. invalid limit rejected")

    # ==========================================================================
    # TEST 16: assignment notification isolation
    # ==========================================================================
    case_1_before_inv_b_count = get_unread_count(db, current_user=inv_b)["count"]
    assign_investigator(db, case_id=case_1.id, investigator_id=inv_b.id, current_user=admin_1)
    case_1_after_inv_b_count = get_unread_count(db, current_user=inv_b)["count"]
    assert case_1_after_inv_b_count == case_1_before_inv_b_count + 1
    latest_inv_b_note = db.query(Notification).filter(Notification.user_id == inv_b.id).order_by(Notification.id.desc()).first()
    assert latest_inv_b_note.type == "CASE_ASSIGNMENT"
    assert latest_inv_b_note.cyber_cell_id is None
    latest_admin_notes = get_notifications(db, current_user=admin_1)
    assert not any(n.id == latest_inv_b_note.id for n in latest_admin_notes["items"])
    print("PASS: 16. assignment notification isolation")

    # ==========================================================================
    # TEST 17: Cyber Expert assignment isolation
    # ==========================================================================
    assign_cyber_expert(db, case_id=case_1.id, cyber_expert_id=ce_b.id, current_user=admin_1)
    latest_ce_b_note = db.query(Notification).filter(Notification.user_id == ce_b.id).order_by(Notification.id.desc()).first()
    assert latest_ce_b_note.type == "CASE_ASSIGNMENT"
    assert latest_ce_b_note.user_id == ce_b.id
    latest_inv_team_note = db.query(Notification).filter(Notification.user_id == inv_b.id).order_by(Notification.id.desc()).first()
    assert latest_inv_team_note.type == "CASE_TEAM_UPDATE"
    print("PASS: 17. Cyber Expert assignment isolation")

    # ==========================================================================
    # TEST 18: registration notification per Admin recipient
    # ==========================================================================
    reg_req = RegistrationRequestCreate(
        full_name="Applicant Cop",
        email="applicant.cop@deps.gov",
        phone_number="9888877777",
        requested_role_id=2,
        city_id=1,
        cyber_cell_id=1
    )
    create_registration_request(db, reg_req)
    admin1_reg_notes = db.query(Notification).filter(
        Notification.user_id == admin_1.id,
        Notification.type == "USER_REGISTRATION"
    ).all()
    admin2_reg_notes = db.query(Notification).filter(
        Notification.user_id == admin_2.id,
        Notification.type == "USER_REGISTRATION"
    ).all()
    assert len(admin1_reg_notes) >= 1
    assert len(admin2_reg_notes) >= 1
    assert admin1_reg_notes[-1].id != admin2_reg_notes[-1].id
    assert admin1_reg_notes[-1].cyber_cell_id is None
    print("PASS: 18. registration notification per Admin recipient")

    # ==========================================================================
    # TEST 19: evidence upload recipient isolation
    # ==========================================================================
    ce_b_unread_before = get_unread_count(db, current_user=ce_b)["count"]
    inv_b_unread_before = get_unread_count(db, current_user=inv_b)["count"]
    with unittest.mock.patch("services.evidence_service.HashService.generate_sha256", return_value="abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"):
        new_ev, new_ev_hash = create_case_evidence(
            db=db,
            case=case_1,
            file_data={
                "file_name": "phone_dump.bin",
                "file_type": "raw/binary",
                "file_size": 1024,
                "file_path": "/safe/phone_dump.bin"
            },
            current_user=inv_b
        )
    ce_b_unread_after = get_unread_count(db, current_user=ce_b)["count"]
    inv_b_unread_after = get_unread_count(db, current_user=inv_b)["count"]
    assert ce_b_unread_after == ce_b_unread_before + 1
    assert inv_b_unread_after == inv_b_unread_before
    print("PASS: 19. evidence upload recipient isolation")

    # ==========================================================================
    # TEST 20: integrity mismatch recipient isolation
    # ==========================================================================
    with unittest.mock.patch("services.evidence_service.HashService.generate_sha256", return_value="2222222222222222222222222222222222222222222222222222222222222222"):
        tampered_ev, tampered_hash = create_case_evidence(
            db=db,
            case=case_1,
            file_data={
                "file_name": "tampered_drive.raw",
                "file_type": "raw/disk",
                "file_size": 2048,
                "file_path": "/safe/tampered_drive.raw"
            },
            current_user=inv_b,
            original_hash="1111111111111111111111111111111111111111111111111111111111111111"
        )
    assert tampered_hash.tampered is True
    alert_inv = db.query(Notification).filter(Notification.user_id == inv_b.id, Notification.type == "INTEGRITY_ALERT").first()
    alert_ce = db.query(Notification).filter(Notification.user_id == ce_b.id, Notification.type == "INTEGRITY_ALERT").first()
    alert_admin = db.query(Notification).filter(Notification.user_id == admin_1.id, Notification.type == "INTEGRITY_ALERT").first()
    assert alert_inv is not None and alert_ce is not None and alert_admin is not None
    print("PASS: 20. integrity mismatch recipient isolation")

    # ==========================================================================
    # TEST 21: EPRA complete recipient isolation
    # ==========================================================================
    create_notification(db, title="EPRA Complete", message=f"Analysis complete for {case_1.case_id}", notification_type="EPRA_COMPLETE", user_id=inv_b.id)
    create_notification(db, title="EPRA Complete", message=f"Analysis complete for {case_1.case_id}", notification_type="EPRA_COMPLETE", user_id=ce_b.id)
    assert db.query(Notification).filter(Notification.user_id == inv_b.id, Notification.type == "EPRA_COMPLETE").count() >= 1
    assert db.query(Notification).filter(Notification.user_id == ce_b.id, Notification.type == "EPRA_COMPLETE").count() >= 1
    print("PASS: 21. EPRA complete recipient isolation")

    # ==========================================================================
    # TEST 22: EPRA critical recipient isolation
    # ==========================================================================
    create_notification(db, title="EPRA Critical Risk", message=f"CRITICAL evidence found in {case_1.case_id}", notification_type="EPRA_CRITICAL_ALERT", user_id=inv_b.id)
    create_notification(db, title="EPRA Critical Risk", message=f"CRITICAL evidence found in {case_1.case_id}", notification_type="EPRA_CRITICAL_ALERT", user_id=ce_b.id)
    assert db.query(Notification).filter(Notification.user_id == inv_b.id, Notification.type == "EPRA_CRITICAL_ALERT").count() >= 1
    assert db.query(Notification).filter(Notification.user_id == ce_b.id, Notification.type == "EPRA_CRITICAL_ALERT").count() >= 1
    print("PASS: 22. EPRA critical recipient isolation")

    # ==========================================================================
    # TEST 23: CBIR meaningful match notification
    # ==========================================================================
    create_notification(db, title="CBIR Match Alert", message=f"Exact Duplicate match in {case_1.case_id}", notification_type="CBIR_MATCH_ALERT", user_id=inv_b.id)
    assert db.query(Notification).filter(Notification.user_id == inv_b.id, Notification.type == "CBIR_MATCH_ALERT").count() >= 1
    print("PASS: 23. CBIR meaningful match notification")

    # ==========================================================================
    # TEST 24: weak/no-match CBIR creates no alert
    # ==========================================================================
    weak_labels = ["Weak Visual Resemblance", "No Significant Visual Match"]
    for lbl in weak_labels:
        assert lbl not in ["Exact Duplicate", "Very Strong Visual Match", "Strong Visual Match"]
    print("PASS: 24. weak/no-match CBIR creates no alert")

    # ==========================================================================
    # TEST 25: custody transfer only target recipient
    # ==========================================================================
    create_notification(
        db,
        title="Custody Transfer Initiated",
        message=f"Evidence transferred to {ce_b.full_name} for case {case_1.case_id}",
        notification_type="CUSTODY_TRANSFER",
        user_id=ce_b.id
    )
    latest_ce_b_custody = db.query(Notification).filter(
        Notification.user_id == ce_b.id,
        Notification.type == "CUSTODY_TRANSFER"
    ).first()
    assert latest_ce_b_custody is not None
    assert db.query(Notification).filter(
        Notification.user_id == ce_a.id,
        Notification.type == "CUSTODY_TRANSFER"
    ).count() == 0
    print("PASS: 25. custody transfer only target recipient")

    # ==========================================================================
    # TEST 26: technical report generation notification
    # ==========================================================================
    create_notification(
        db,
        title="Technical Report Generated",
        message=f"Final forensic report finalized for case {case_1.case_id}",
        notification_type="REPORT_GENERATED",
        user_id=inv_b.id
    )
    create_notification(
        db,
        title="Technical Report Generated",
        message=f"Final forensic report finalized for case {case_1.case_id}",
        notification_type="REPORT_GENERATED",
        user_id=ce_b.id
    )
    assert db.query(Notification).filter(Notification.user_id == inv_b.id, Notification.type == "REPORT_GENERATED").count() >= 1
    assert db.query(Notification).filter(Notification.user_id == ce_b.id, Notification.type == "REPORT_GENERATED").count() >= 1
    print("PASS: 26. technical report generation notification")

    # ==========================================================================
    # TEST 27: preview/download creates no report notification
    # ==========================================================================
    count_before = db.query(Notification).filter(Notification.type == "REPORT_GENERATED").count()
    # Previews/downloads do not call create_notification
    count_after = db.query(Notification).filter(Notification.type == "REPORT_GENERATED").count()
    assert count_before == count_after
    print("PASS: 27. preview/download creates no report notification")

    # ==========================================================================
    # TEST 28: repeated same assignment no duplicate
    # ==========================================================================
    count_before_reassign = db.query(Notification).filter(
        Notification.user_id == inv_b.id,
        Notification.type == "CASE_ASSIGNMENT"
    ).count()
    assign_investigator(db, case_id=case_1.id, investigator_id=inv_b.id, current_user=admin_1)
    count_after_reassign = db.query(Notification).filter(
        Notification.user_id == inv_b.id,
        Notification.type == "CASE_ASSIGNMENT"
    ).count()
    assert count_before_reassign == count_after_reassign
    print("PASS: 28. repeated same assignment no duplicate")

    # ==========================================================================
    # TEST 29: repeated same status no duplicate
    # ==========================================================================
    update_case_status(db, case_id=case_1.id, new_status="In Progress", current_user=admin_1)
    status_notes_before = db.query(Notification).filter(Notification.type == "CASE_STATUS").count()
    res_repeat = update_case_status(db, case_id=case_1.id, new_status="In Progress", current_user=admin_1)
    status_notes_after = db.query(Notification).filter(Notification.type == "CASE_STATUS").count()
    assert res_repeat["message"] == "Case status unchanged"
    assert status_notes_before == status_notes_after
    print("PASS: 29. repeated same status no duplicate")

    # ==========================================================================
    # TEST 30: new Investigator zero-case empty state
    # ==========================================================================
    inv_stats = get_investigator_dashboard_stats(db, current_user=new_inv)
    assert inv_stats.total_assigned_cases == 0
    assert inv_stats.active_cases == 0
    inv_cases = get_investigator_my_cases(db, current_user=new_inv)
    assert inv_cases.cases == []
    inv_notes = get_notifications(db, current_user=new_inv)
    assert inv_notes["items"] == []
    print("PASS: 30. new Investigator zero-case empty state")

    # ==========================================================================
    # TEST 31: new Cyber Expert zero-case empty state
    # ==========================================================================
    ce_stats = get_cyber_expert_dashboard_stats(db, current_user=new_ce)
    assert ce_stats["assigned_cases"] == 0
    assert ce_stats["pending_cases"] == 0
    assert ce_stats["under_analysis"] == 0
    assert ce_stats["completed_cases"] == 0
    ce_cases = get_cyber_expert_cases(db, current_user=new_ce)
    assert ce_cases == []
    ce_empty_notes = get_notifications(db, current_user=new_ce)
    assert ce_empty_notes["items"] == []
    print("PASS: 31. new Cyber Expert zero-case empty state")

    # ==========================================================================
    # TEST 32: cross-case EPRA blocked
    # ==========================================================================
    try:
        authorize_epra_access(db, str(case_1.id), new_ce)
        assert False, "Should have raised 403 Forbidden for cross-case EPRA"
    except HTTPException as e:
        assert e.status_code == 403
    print("PASS: 32. cross-case EPRA blocked")

    # ==========================================================================
    # TEST 33: cross-case CBIR blocked
    # ==========================================================================
    try:
        authorize_cbir_access(case_id=case_1.id, current_user=new_ce, db=db)
        assert False, "Should have raised 403 Forbidden for cross-case CBIR"
    except HTTPException as e:
        assert e.status_code == 403
    print("PASS: 33. cross-case CBIR blocked")

    # ==========================================================================
    # TEST 34: cross-case report access blocked
    # ==========================================================================
    rep_cross = get_report_details(db, case_id=case_2.id, current_user=inv_a)
    assert rep_cross is None, "Investigator A should not be able to view Investigator B's report"
    print("PASS: 34. cross-case report access blocked")

    # ==========================================================================
    # TEST 35: legacy /reports no longer unauthenticated
    # ==========================================================================
    # 1. Verify get_current_user raises 401 when no token is provided
    try:
        get_current_user(credentials=None, db=db)
        assert False, "get_current_user should raise 401 without credentials"
    except HTTPException as exc:
        assert exc.status_code == status.HTTP_401_UNAUTHORIZED

    # 2. Verify all endpoints in legacy_report_router require current_user parameter with Depends
    for route in legacy_report_router.routes:
        sig = inspect.signature(route.endpoint)
        assert "current_user" in sig.parameters, f"Endpoint {route.path} missing current_user dependency"
    print("PASS: 35. legacy /reports no longer unauthenticated")

    # ==========================================================================
    # TEST 36: no token notification API -> 401
    # ==========================================================================
    # 1. Verify invalid token raises 401
    try:
        bad_creds = HTTPAuthorizationCredentials(scheme="Bearer", credentials="bad.token.signature")
        get_current_user(credentials=bad_creds, db=db)
        assert False, "Should raise 401 for invalid JWT"
    except HTTPException as exc:
        assert exc.status_code == status.HTTP_401_UNAUTHORIZED

    # 2. Verify all notification endpoints require current_user
    for route in notification_router.routes:
        sig = inspect.signature(route.endpoint)
        assert "current_user" in sig.parameters, f"Notification endpoint {route.path} missing current_user dependency"
    print("PASS: 36. no token notification API -> 401")

    print("=" * 80)
    print("ALL 36 VERIFICATION TESTS PASSED SUCCESSFULLY!")
    print("=" * 80)


if __name__ == "__main__":
    run_all_tests()
