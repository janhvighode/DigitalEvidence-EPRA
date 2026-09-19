import pytest
from datetime import datetime, timezone, timedelta
from pathlib import Path
from uuid import uuid4
from fastapi import HTTPException
from fastapi.responses import FileResponse

from database.database import SessionLocal
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.user import User
from models.role import Role
from models.custody_log import CustodyLog
from models.current_custody import CurrentCustodyInfo
from models.transfer_record import TransferRecord
from services.custody_service import CustodyService
from services.custody_adapter import CustodyAdapter
from services.storage_service import StorageService
from schemas.custody import CurrentCustodyUpdateRequest
from routes.custody_routes import (
    get_custody_timeline,
    get_current_custody,
    update_current_custody,
    get_transfer_history,
    initiate_transfer,
    receive_transfer,
    record_evidence_access,
    get_evidence_custody_details,
    preview_evidence_image,
    verify_cyber_expert_case_access,
    verify_evidence_in_case
)
from routes.evidence_routes import preview_evidence


@pytest.fixture
def db():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


@pytest.fixture
def test_setup(db, tmp_path):
    """Create controlled test fixtures for Case, Users, Roles, Evidence, and Binary file."""
    # Ensure standard roles exist
    r_admin = db.query(Role).filter(Role.id == 1).first()
    if not r_admin:
        r_admin = Role(id=1, role_name="Administrator")
        db.add(r_admin)
    r_inv = db.query(Role).filter(Role.id == 2).first()
    if not r_inv:
        r_inv = Role(id=2, role_name="Investigator")
        db.add(r_inv)
    r_ce = db.query(Role).filter(Role.id == 3).first()
    if not r_ce:
        r_ce = Role(id=3, role_name="Cyber Expert")
        db.add(r_ce)
    db.commit()

    suffix = uuid4().hex[:6]

    # Create users
    inv_user = User(
        full_name=f"Test Investigator {suffix}",
        username=f"test_inv_{suffix}",
        email=f"test_inv_{suffix}@deps.local",
        phone_number="1234567890",
        password="hashed_pw",
        role_id=2,
        cyber_cell_id=1,
        is_active=True
    )
    ce_user = User(
        full_name=f"Test CyberExpert {suffix}",
        username=f"test_ce_{suffix}",
        email=f"test_ce_{suffix}@deps.local",
        phone_number="1234567891",
        password="hashed_pw",
        role_id=3,
        cyber_cell_id=1,
        is_active=True
    )
    unassigned_user = User(
        full_name=f"Test Unassigned {suffix}",
        username=f"test_unassigned_{suffix}",
        email=f"test_unassigned_{suffix}@deps.local",
        phone_number="1234567892",
        password="hashed_pw",
        role_id=3,
        cyber_cell_id=1,
        is_active=True
    )
    db.add_all([inv_user, ce_user, unassigned_user])
    db.commit()
    db.refresh(inv_user)
    db.refresh(ce_user)
    db.refresh(unassigned_user)

    # Create test case
    test_case = Case(
        case_id=f"CASE-TEST-{suffix}",
        title=f"Test Custody Case {suffix}",
        description="Testing Chain of Custody fixes",
        crime_type="Cyber Fraud",
        investigator_id=inv_user.id,
        cyber_expert_id=ce_user.id,
        priority="High",
        status="Open",
        created_by=inv_user.id
    )
    db.add(test_case)
    db.commit()
    db.refresh(test_case)

    # Create a real image binary file in StorageService storage root
    real_img_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x01\x00H\x00H\x00\x00\xff\xdb\x00C\x00\x08\x06\x06\x07\x06\x05\x08\x07\x07\x07\t\t\x08\n\x0c\x14\r\x0c\x0b\x0b\x0c\x19\x12\x13\x0f\x14\x1d\x1a\x1f\x1e\x1d\x1a\x1c\x1c $.' \",#\x1c\x1c(7),01444\x1f'9=82<.342\xff\xc0\x00\x0b\x08\x00\x01\x00\x01\x01\x01\x11\x00\xff\xc4\x00\x1f\x00\x00\x01\x05\x01\x01\x01\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x01\x02\x03\x04\x05\x06\x07\x08\t\n\x0b\xff\xda\x00\x08\x01\x01\x00\x00?\x00\xbf\x00\xff\xd9"
    storage_case_dir = StorageService.get_storage_root() / str(test_case.id)
    storage_case_dir.mkdir(parents=True, exist_ok=True)
    img_path = storage_case_dir / f"test_evidence_{suffix}.jpg"
    img_path.write_bytes(real_img_bytes)

    rel_file_path = f"uploads/evidence/{test_case.id}/test_evidence_{suffix}.jpg"

    # Create Evidence with existing binary
    ev_with_binary = Evidence(
        evidence_id=f"EV-TEST-{suffix}-001",
        case_id=test_case.id,
        file_name=f"test_evidence_{suffix}.jpg",
        file_type="image/jpeg",
        file_size=len(real_img_bytes),
        file_path=rel_file_path,
        status="Active"
    )
    # Create Evidence with missing binary (simulating historical lost disk container)
    ev_missing_binary = Evidence(
        evidence_id=f"EV-TEST-{suffix}-002",
        case_id=test_case.id,
        file_name=f"missing_evidence_{suffix}.jpg",
        file_type="image/jpeg",
        file_size=1024,
        file_path=f"uploads/evidence/{test_case.id}/nonexistent_{suffix}.jpg",
        status="Active"
    )
    # Create non-image Evidence (PDF)
    ev_pdf = Evidence(
        evidence_id=f"EV-TEST-{suffix}-003",
        case_id=test_case.id,
        file_name=f"document_{suffix}.pdf",
        file_type="application/pdf",
        file_size=2048,
        file_path=f"uploads/evidence/{test_case.id}/document_{suffix}.pdf",
        status="Active"
    )
    db.add_all([ev_with_binary, ev_missing_binary, ev_pdf])
    db.commit()
    db.refresh(ev_with_binary)
    db.refresh(ev_missing_binary)
    db.refresh(ev_pdf)

    # Create EvidenceHash records
    h1 = EvidenceHash(
        evidence_id=ev_with_binary.id,
        file_name=ev_with_binary.file_name,
        sha256_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        current_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        original_hash="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
        hash_match=True,
        tampered=False,
        integrity_status="Verified",
        verified_at=datetime.now(timezone.utc),
        verified_by=inv_user.id  # Verified by Investigator!
    )
    db.add(h1)
    db.commit()

    return {
        "case": test_case,
        "inv_user": inv_user,
        "ce_user": ce_user,
        "unassigned_user": unassigned_user,
        "ev_with_binary": ev_with_binary,
        "ev_missing_binary": ev_missing_binary,
        "ev_pdf": ev_pdf,
        "real_img_bytes": real_img_bytes,
        "hash1": h1
    }


# ============================================================
# PART 1: WRONG TIMELINE ACTOR ROLE
# ============================================================

def test_actor_role_dynamic_resolution(db, test_setup):
    """
    Verify that an event where actor is an Investigator (e.g. Khushal Narnaware / inv_user)
    resolves to 'Investigator', and actor as Cyber Expert resolves to 'Cyber Expert'.
    Never hardcoded to 'Cyber Expert'.
    """
    case = test_setup["case"]
    inv_user = test_setup["inv_user"]
    ce_user = test_setup["ce_user"]
    ev = test_setup["ev_with_binary"]

    # 1. Sync authentic evidence events (includes HASH_GENERATED verified by inv_user)
    CustodyAdapter.sync_authentic_evidence_events(db, case.id, ce_user)

    # 2. Query timeline for the evidence
    timeline = CustodyService.get_custody_timeline(db, evidence_id=ev.evidence_id, case_id=str(case.id))

    # Find the HASH_GENERATED event verified by inv_user
    hash_events = [e for e in timeline if e["event_type"] == "HASH_GENERATED"]
    assert len(hash_events) >= 1, "Expected HASH_GENERATED event in timeline"
    hash_event = hash_events[0]

    # Authoritative DB role of inv_user is Investigator (role_id=2)
    assert hash_event["actor_id"] == str(inv_user.id)
    assert hash_event["actor_name"] == (inv_user.full_name or inv_user.username)
    assert hash_event["actor_role"] == "Investigator", f"Expected 'Investigator' but got '{hash_event['actor_role']}'"

    # 3. Add an event performed by ce_user
    ce_log = CustodyService.create_log(
        db=db,
        evidence_id=ev.evidence_id,
        investigator_name=ce_user.full_name,
        investigator_id=str(ce_user.id),
        action="ANALYSIS_PERFORMED",
        case_id=str(case.id)
    )
    timeline_after = CustodyService.get_custody_timeline(db, evidence_id=ev.evidence_id, case_id=str(case.id))
    ce_events = [e for e in timeline_after if e["event_type"] == "ANALYSIS_PERFORMED"]
    assert len(ce_events) >= 1
    assert ce_events[0]["actor_role"] == "Cyber Expert", f"Expected 'Cyber Expert' but got '{ce_events[0]['actor_role']}'"


# ============================================================
# PART 2: CUSTODY TIMELINE CORRECTNESS & DEBOUNCE
# ============================================================

def test_timeline_duplicate_debounce(db, test_setup):
    """
    Verify that rapid successive calls to record_access_event (e.g. frontend rebuilds)
    do not insert duplicate CustodyLog audit records.
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    ev = test_setup["ev_with_binary"]

    # Initial access event count
    initial_count = db.query(CustodyLog).filter(
        CustodyLog.evidence_id == ev.evidence_id,
        CustodyLog.action == "ACCESSED_FOR_ANALYSIS"
    ).count()

    # 1. First access call
    res1 = record_evidence_access(
        case_id=case.id,
        evidence_id=ev.evidence_id,
        purpose="Forensic analysis",
        db=db,
        current_user=ce_user
    )
    assert res1["status"] == "success"

    # 2. Second rapid access call (simulating widget rebuild or duplicate API call)
    res2 = record_evidence_access(
        case_id=case.id,
        evidence_id=ev.evidence_id,
        purpose="Forensic analysis",
        db=db,
        current_user=ce_user
    )
    assert res2["status"] == "success"
    assert res2.get("debounced") is True, "Expected second rapid call to be debounced"

    # Count must only have incremented by 1
    new_count = db.query(CustodyLog).filter(
        CustodyLog.evidence_id == ev.evidence_id,
        CustodyLog.action == "ACCESSED_FOR_ANALYSIS"
    ).count()
    assert new_count == initial_count + 1, f"Expected {initial_count + 1} access logs, found {new_count}"


def test_timeline_ordering_and_no_fake_events_on_page_load(db, test_setup):
    """
    Verify that calling GET /summary, GET /timeline, GET /current does NOT create fake access events.
    Verify timeline ordering is chronological (timestamp ascending).
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    ev = test_setup["ev_with_binary"]

    access_count_before = db.query(CustodyLog).filter(
        CustodyLog.evidence_id == ev.evidence_id,
        CustodyLog.action == "ACCESSED_FOR_ANALYSIS"
    ).count()

    # Call timeline endpoint (simulating page load)
    tl_resp = get_custody_timeline(
        case_id=case.id,
        evidence_id=ev.evidence_id,
        event_filter="ALL",
        db=db,
        current_user=ce_user
    )
    # Call current custody endpoint
    get_current_custody(case_id=case.id, evidence_id=ev.evidence_id, db=db, current_user=ce_user)

    access_count_after = db.query(CustodyLog).filter(
        CustodyLog.evidence_id == ev.evidence_id,
        CustodyLog.action == "ACCESSED_FOR_ANALYSIS"
    ).count()
    assert access_count_after == access_count_before, "Page load must NOT create access events"

    # Verify timeline ordering
    events = tl_resp["events"]
    if len(events) >= 2:
        for i in range(len(events) - 1):
            assert events[i]["timestamp"] <= events[i + 1]["timestamp"], "Timeline must be sorted chronologically ascending"


# ============================================================
# PART 3: CURRENT CUSTODY INFORMATION & PERSISTENCE
# ============================================================

def test_current_custody_persistence_and_retrieval(db, test_setup):
    """
    Verify full save flow: update current custody with holder, department, location, remarks.
    Verify that values survive DB session refresh and are returned by GET /current.
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    inv_user = test_setup["inv_user"]
    ev = test_setup["ev_with_binary"]

    payload = CurrentCustodyUpdateRequest(
        department="Forensic Cyber Unit",
        location="Secure Locker B-12",
        remarks="Assigned to senior investigator for technical inspection",
        current_holder_id=str(inv_user.id),
        current_holder_name=inv_user.full_name,
        current_holder_role="Investigator",
        custody_status="In Custody"
    )

    # 1. Update custody
    update_resp = update_current_custody(
        case_id=case.id,
        payload=payload,
        evidence_id=ev.evidence_id,
        db=db,
        current_user=ce_user
    )

    assert update_resp["current_holder_name"] == inv_user.full_name
    assert update_resp["current_holder_role"] == "Investigator"
    assert update_resp["department"] == "Forensic Cyber Unit"
    assert update_resp["location"] == "Secure Locker B-12"
    assert update_resp["remarks"] == "Assigned to senior investigator for technical inspection"
    assert update_resp["custody_status"] == "In Custody"

    # 2. Fresh session query
    fresh_session = SessionLocal()
    try:
        fresh_info = fresh_session.query(CurrentCustodyInfo).filter(
            CurrentCustodyInfo.evidence_id == ev.evidence_id
        ).first()
        assert fresh_info is not None
        assert fresh_info.current_holder_name == inv_user.full_name
        assert fresh_info.department == "Forensic Cyber Unit"
        assert fresh_info.location == "Secure Locker B-12"
        assert fresh_info.custody_status == "In Custody"

        # 3. GET /current API
        get_resp = get_current_custody(
            case_id=case.id,
            evidence_id=ev.evidence_id,
            db=fresh_session,
            current_user=ce_user
        )
        assert get_resp["current_holder_name"] == inv_user.full_name
        assert get_resp["department"] == "Forensic Cyber Unit"
        assert get_resp["location"] == "Secure Locker B-12"
    finally:
        fresh_session.close()


# ============================================================
# PART 4: TRANSFER HISTORY
# ============================================================

def test_transfer_workflow_and_scoping(db, test_setup):
    """
    Verify:
    1. Accessing evidence does NOT increment transfer count.
    2. Genuine transfer initiation -> PENDING_RECEIPT.
    3. Transfer receipt -> COMPLETED, updates current holder, increments transfer count.
    4. Scoped to selected evidence.
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    inv_user = test_setup["inv_user"]
    ev = test_setup["ev_with_binary"]

    # 1. Check initial transfer summary
    summary_before = CustodyService.get_custody_summary(db, ev.evidence_id)
    initial_transfers = summary_before["transfers_count"]

    # 2. Access evidence -> should NOT increment transfer count
    CustodyService.record_access_event(
        db=db,
        evidence_id=ev.evidence_id,
        actor_name=ce_user.full_name,
        actor_id=str(ce_user.id),
        case_id=str(case.id)
    )
    summary_after_access = CustodyService.get_custody_summary(db, ev.evidence_id)
    assert summary_after_access["transfers_count"] == initial_transfers, "Access must NOT increment transfer count"

    # 3. Genuine transfer initiation
    tr_init = CustodyService.initiate_transfer(
        db=db,
        evidence_id=ev.evidence_id,
        sender_name=ce_user.full_name,
        recipient_name=inv_user.full_name,
        sender_id=str(ce_user.id),
        recipient_id=str(inv_user.id),
        remarks="Handing over for court presentation",
        case_id=str(case.id)
    )
    assert tr_init["status"] == "PENDING_RECEIPT"
    transfer_ref = tr_init["transfer_reference"]

    # Transfers card counts COMPLETED transfers only
    summary_pending = CustodyService.get_custody_summary(db, ev.evidence_id)
    assert summary_pending["transfers_count"] == initial_transfers
    assert summary_pending["pending_transfers"] == 1

    # 4. Confirm receipt
    tr_recv = CustodyService.receive_transfer(
        db=db,
        transfer_reference=transfer_ref,
        recipient_name=inv_user.full_name,
        recipient_id=str(inv_user.id),
        recipient_role="Investigator",
        department="Police Cyber Cell",
        location="Locker 4",
        remarks="Received in sealed evidence bag"
    )
    assert tr_recv["status"] == "COMPLETED"

    # Transfers count should now increment by 1
    summary_completed = CustodyService.get_custody_summary(db, ev.evidence_id)
    assert summary_completed["transfers_count"] == initial_transfers + 1
    assert summary_completed["pending_transfers"] == 0

    # Verify transfer history table contains the record
    th = CustodyService.get_transfer_history(db, evidence_id=ev.evidence_id, case_id=str(case.id))
    refs = [t["transfer_reference"] for t in th["transfers"]]
    assert transfer_ref in refs


# ============================================================
# PART 5: EVIDENCE DETAILS BACKEND DATA
# ============================================================

def test_evidence_custody_details_enrichment(db, test_setup):
    """
    Verify GET /evidence/{evidence_id} returns all required fields:
    Evidence ID, filename, canonical type, MIME, size, upload timestamp,
    uploaded by, SHA-256, integrity status, current custodian, last accessed.
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    ev = test_setup["ev_with_binary"]

    details = get_evidence_custody_details(
        case_id=case.id,
        evidence_id=ev.evidence_id,
        db=db,
        current_user=ce_user
    )

    assert details["evidence_id"] == ev.evidence_id
    assert details["file_name"] == ev.file_name
    assert details["original_filename"] == ev.file_name
    assert details["canonical_type"] == "IMAGE"
    assert details["evidence_type"] == "IMAGE"
    assert details["mime_type"] == "image/jpeg"
    assert details["file_size"] == ev.file_size
    assert details["file_size_bytes"] == ev.file_size
    assert details["created_at"] is not None
    assert details["upload_timestamp"] is not None
    assert details["original_sha256"] is not None
    assert details["current_hash"] is not None
    assert details["integrity_status"] == "Verified"
    assert details["preview_url"] == f"/cases/{case.id}/chain-of-custody/evidence/{ev.evidence_id}/preview"
    assert details["download_url"] == f"/cases/{case.id}/evidence/{ev.evidence_id}/download"


# ============================================================
# PART 6 & 7: IMAGE PREVIEW BACKEND & MISSING BINARY BEHAVIOR
# ============================================================

def test_image_preview_returns_real_bytes(db, test_setup):
    """
    For IMAGE evidence whose binary exists:
    Verify preview endpoint returns HTTP 200, Content-Type image/jpeg, and real image bytes.
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    ev = test_setup["ev_with_binary"]

    resp = preview_evidence_image(
        case_id=case.id,
        evidence_id=ev.evidence_id,
        db=db,
        current_user=ce_user
    )

    assert isinstance(resp, FileResponse)
    assert resp.media_type in ["image/jpeg", "image/jpg"]
    assert Path(resp.path).is_file()
    assert Path(resp.path).read_bytes() == test_setup["real_img_bytes"]


def test_missing_binary_returns_404(db, test_setup):
    """
    For historical evidence whose DB record exists but physical binary is missing on disk:
    Verify preview endpoint raises HTTP 404 (does NOT return fake image or placeholder).
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    ev_missing = test_setup["ev_missing_binary"]

    with pytest.raises(HTTPException) as exc_info:
        preview_evidence_image(
            case_id=case.id,
            evidence_id=ev_missing.evidence_id,
            db=db,
            current_user=ce_user
        )
    assert exc_info.value.status_code == 404
    assert "not found" in str(exc_info.value.detail).lower()


def test_non_image_preview_rejected(db, test_setup):
    """
    For non-image evidence (PDF):
    Verify preview endpoint rejects with HTTP 400.
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    ev_pdf = test_setup["ev_pdf"]

    with pytest.raises(HTTPException) as exc_info:
        preview_evidence_image(
            case_id=case.id,
            evidence_id=ev_pdf.evidence_id,
            db=db,
            current_user=ce_user
        )
    assert exc_info.value.status_code == 400
    assert "only supported for image evidence" in str(exc_info.value.detail).lower()


# ============================================================
# PART 8 & 10: AUTHORIZATION & ISOLATION
# ============================================================

def test_authorization_controls(db, test_setup):
    """
    Verify:
    1. Assigned Cyber Expert -> Allowed.
    2. Assigned Investigator -> Allowed.
    3. Unassigned user -> 403 Forbidden.
    4. Nonexistent evidence -> 404 Not Found.
    5. Foreign case evidence -> 404 Not Found (no cross-case leakage).
    """
    case = test_setup["case"]
    ce_user = test_setup["ce_user"]
    inv_user = test_setup["inv_user"]
    unassigned_user = test_setup["unassigned_user"]
    ev = test_setup["ev_with_binary"]

    # 1. Assigned Cyber Expert -> Allowed
    c1 = verify_cyber_expert_case_access(case.id, ce_user, db)
    assert c1.id == case.id

    # 2. Assigned Investigator -> Allowed
    c2 = verify_cyber_expert_case_access(case.id, inv_user, db)
    assert c2.id == case.id

    # 3. Unassigned user -> 403 Forbidden
    with pytest.raises(HTTPException) as exc_403:
        verify_cyber_expert_case_access(case.id, unassigned_user, db)
    assert exc_403.value.status_code == 403

    # 4. Nonexistent evidence -> 404 Not Found
    with pytest.raises(HTTPException) as exc_404:
        verify_evidence_in_case(case.id, "NONEXISTENT-EVIDENCE-ID", db)
    assert exc_404.value.status_code == 404

    # 5. Foreign case evidence -> 404 Not Found
    other_case = Case(
        case_id=f"CASE-OTHER-{uuid4().hex[:8]}",
        title="Other Case",
        investigator_id=inv_user.id,
        cyber_expert_id=ce_user.id,
        created_by=inv_user.id
    )
    db.add(other_case)
    db.commit()
    db.refresh(other_case)

    with pytest.raises(HTTPException) as exc_foreign:
        verify_evidence_in_case(other_case.id, ev.evidence_id, db)
    assert exc_foreign.value.status_code == 404
