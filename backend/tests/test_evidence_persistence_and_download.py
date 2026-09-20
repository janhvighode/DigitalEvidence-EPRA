"""
Comprehensive Test Suite for Evidence Durable File Persistence & Retrieval Fix.

Verifies:
1. Upload stores real binary to durable persistent storage
2. Stable storage reference persists in DB (relative durable path)
3. Download returns HTTP 200
4. Response body equals original uploaded bytes byte-for-byte
5. SHA-256 upload == SHA-256 download
6. Content-Type matches legitimate evidence MIME type
7. Content-Disposition contains attachment with sanitized original filename
8. Unauthorized download blocked (403 Forbidden)
9. Nonexistent evidence record returns 404 (Evidence not found)
10. Evidence row with missing binary returns 404 ("Evidence file is not available in persistent storage.")
11. Second case works independently (multi-case isolation)
12. Fresh session/process-style retrieval works without in-memory state
"""

import os
import io
import hashlib
import tempfile
import sys
from pathlib import Path
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException, UploadFile
from fastapi.responses import FileResponse

# Ensure backend directory is in sys.path
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
from models.case_timeline import CaseTimeline
from models.evidence_record import EvidenceRecord
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.notification import Notification
from models.report_record import ReportRecord
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink
from models.cbir_result import CBIRResult

from services.storage_service import StorageService
from services.evidence_service import (
    create_case_evidence,
    get_case_evidence_download,
    authorize_case_access
)
from routes.evidence_routes import download_evidence
from routes.investigator_dashboard_routes import download_evidence_file as investigator_download


def setup_test_environment(tmp_path):
    """Sets up an isolated SQLite in-memory DB and temporary durable storage directory."""
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
            CaseTimeline.__table__,
            EvidenceRecord.__table__,
            CustodyLog.__table__,
            ActivityLog.__table__,
            Notification.__table__,
            ReportRecord.__table__,
            PossibleEntity.__table__,
            PossibleEntityEvidenceLink.__table__,
            EvidenceLink.__table__,
            CBIRResult.__table__
        ]
    )
    TestSession = sessionmaker(autocommit=False, autoflush=False, bind=engine)
    db = TestSession()

    # Point durable storage to a temporary directory
    durable_dir = tmp_path / "durable_evidence_vault"
    durable_dir.mkdir(parents=True, exist_ok=True)
    os.environ["EVIDENCE_STORAGE_PATH"] = str(durable_dir)

    # Seed City
    city = City(id=1, city_name="Metropolis")
    db.add(city)

    # Seed roles
    roles = [
        Role(id=1, role_name="Administrator"),
        Role(id=2, role_name="Investigator"),
        Role(id=3, role_name="Cyber Expert")
    ]
    db.add_all(roles)

    # Seed CyberCell
    cell = CyberCell(id=1, cyber_cell_name="Unit Alpha", admin_email="admin@alpha.gov", city_id=1)
    db.add(cell)

    # Seed Users
    admin = User(
        id=1, username="admin_user", full_name="Admin User",
        email="admin@test.gov", phone_number="9000000001", password="hash",
        role_id=1, cyber_cell_id=1, is_active=True
    )
    inv1 = User(
        id=2, username="inv_smith", full_name="John Smith",
        email="smith@test.gov", phone_number="9000000002", password="hash",
        role_id=2, cyber_cell_id=1, is_active=True
    )
    inv2 = User(
        id=3, username="inv_doe", full_name="Jane Doe",
        email="doe@test.gov", phone_number="9000000003", password="hash",
        role_id=2, cyber_cell_id=1, is_active=True
    )
    expert = User(
        id=4, username="expert_dave", full_name="Dave Forensic",
        email="dave@test.gov", phone_number="9000000004", password="hash",
        role_id=3, cyber_cell_id=1, is_active=True
    )
    db.add_all([admin, inv1, inv2, expert])

    # Seed Case 1 (Assigned to inv1, expert)
    case_1 = Case(
        id=101, case_id="CASE-2026-001", title="Phishing Investigation",
        created_by=admin.id, investigator_id=inv1.id, cyber_expert_id=expert.id,
        status="Open"
    )
    # Seed Case 2 (Assigned to inv2, expert)
    case_2 = Case(
        id=102, case_id="CASE-2026-002", title="Ransomware Outbreak",
        created_by=admin.id, investigator_id=inv2.id, cyber_expert_id=expert.id,
        status="Open"
    )
    db.add_all([case_1, case_2])
    db.commit()

    return db, TestSession, durable_dir, {
        "admin": admin,
        "inv1": inv1,
        "inv2": inv2,
        "expert": expert,
        "case_1": case_1,
        "case_2": case_2
    }


def test_1_upload_and_durable_persistence(tmp_path):
    """1. Upload stores real binary in durable storage root and records stable storage reference."""
    import asyncio
    db, TestSession, durable_dir, fixtures = setup_test_environment(tmp_path)
    case_1 = fixtures["case_1"]
    inv1 = fixtures["inv1"]

    raw_bytes = b"MALICIOUS_PAYLOAD_FORENSIC_SAMPLE_BYTES_12345"
    orig_hash = hashlib.sha256(raw_bytes).hexdigest()
    test_upload = UploadFile(
        file=io.BytesIO(raw_bytes),
        filename="malware_sample.bin"
    )

    file_data = asyncio.run(StorageService.save_uploaded_file(test_upload, case_1.id))
    assert file_data["file_name"] == "malware_sample.bin"
    assert file_data["file_size"] == len(raw_bytes)
    assert file_data["file_path"].startswith(f"uploads/evidence/{case_1.id}/")

    # Verify physical file was written to durable storage root
    resolved_path = StorageService.resolve_evidence_path(file_data["file_path"], case_1.id)
    assert resolved_path is not None
    assert resolved_path.is_file()
    assert resolved_path.read_bytes() == raw_bytes
    assert resolved_path.is_relative_to(durable_dir)

    # Create Evidence DB record
    new_evidence, new_hash = create_case_evidence(
        db=db,
        case=case_1,
        file_data=file_data,
        current_user=inv1,
        original_hash=orig_hash
    )

    assert new_evidence.id is not None
    assert new_evidence.file_path == file_data["file_path"]
    assert new_hash.current_hash == orig_hash
    assert new_hash.integrity_status == "Verified"

    print("PASS: test_1_upload_and_durable_persistence")


def test_2_download_success_and_forensic_integrity(tmp_path):
    """2, 3, 4, 5, 6, 7. Download returns HTTP 200, matching bytes, exact SHA-256, Content-Type, Content-Disposition."""
    import asyncio
    db, TestSession, durable_dir, fixtures = setup_test_environment(tmp_path)
    case_1 = fixtures["case_1"]
    inv1 = fixtures["inv1"]

    # Image test file
    img_bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15c4"
    img_hash = hashlib.sha256(img_bytes).hexdigest()
    test_upload = UploadFile(
        file=io.BytesIO(img_bytes),
        filename="evidence_screenshot.png"
    )

    file_data = asyncio.run(StorageService.save_uploaded_file(test_upload, case_1.id))
    new_evidence, _ = create_case_evidence(
        db=db,
        case=case_1,
        file_data=file_data,
        current_user=inv1,
        original_hash=img_hash
    )

    # 1. Download via evidence_routes endpoint
    response = download_evidence(
        case_id=case_1.case_id,
        evidence_id=new_evidence.evidence_id,
        current_user=inv1,
        db=db
    )
    assert isinstance(response, FileResponse)
    assert response.status_code == 200
    assert response.media_type == "image/png"
    assert response.filename == "evidence_screenshot.png"
    assert 'attachment; filename="evidence_screenshot.png"' in response.headers["Content-Disposition"]

    # Verify downloaded bytes and SHA-256 byte-for-byte
    dl_path = Path(response.path)
    dl_bytes = dl_path.read_bytes()
    assert dl_bytes == img_bytes
    dl_hash = hashlib.sha256(dl_bytes).hexdigest()
    assert dl_hash == img_hash

    # 2. Download via investigator_dashboard_routes endpoint
    inv_resp = investigator_download(
        case_id=case_1.case_id,
        evidence_id=new_evidence.evidence_id,
        current_user=inv1,
        db=db
    )
    assert isinstance(inv_resp, FileResponse)
    assert inv_resp.status_code == 200
    assert inv_resp.filename == "evidence_screenshot.png"
    assert Path(inv_resp.path).read_bytes() == img_bytes

    print("PASS: test_2_download_success_and_forensic_integrity")


def test_3_unauthorized_download_blocked(tmp_path):
    """8. Unauthorized user cannot download evidence from another case."""
    import asyncio
    db, TestSession, durable_dir, fixtures = setup_test_environment(tmp_path)
    case_1 = fixtures["case_1"]
    inv1 = fixtures["inv1"]
    inv2 = fixtures["inv2"]  # Assigned to Case 2, NOT Case 1

    test_upload = UploadFile(file=io.BytesIO(b"CONFIDENTIAL_DATA"), filename="confidential.txt")
    file_data = asyncio.run(StorageService.save_uploaded_file(test_upload, case_1.id))
    new_evidence, _ = create_case_evidence(db=db, case=case_1, file_data=file_data, current_user=inv1)

    # Inv2 trying to download Case 1 evidence -> 403 Forbidden
    with pytest.raises(HTTPException) as exc_info:
        download_evidence(
            case_id=case_1.case_id,
            evidence_id=new_evidence.evidence_id,
            current_user=inv2,
            db=db
        )
    assert exc_info.value.status_code == 403
    assert "Access denied" in exc_info.value.detail

    print("PASS: test_3_unauthorized_download_blocked")


def test_4_nonexistent_evidence_returns_404(tmp_path):
    """9. Nonexistent evidence record returns 404."""
    db, TestSession, durable_dir, fixtures = setup_test_environment(tmp_path)
    case_1 = fixtures["case_1"]
    inv1 = fixtures["inv1"]

    with pytest.raises(HTTPException) as exc_info:
        download_evidence(
            case_id=case_1.case_id,
            evidence_id="EV-NON-EXISTENT-999",
            current_user=inv1,
            db=db
        )
    assert exc_info.value.status_code == 404
    assert "not found" in exc_info.value.detail

    print("PASS: test_4_nonexistent_evidence_returns_404")


def test_5_missing_binary_returns_clear_storage_404(tmp_path):
    """10. Existing DB record with missing physical binary returns clear 404."""
    db, TestSession, durable_dir, fixtures = setup_test_environment(tmp_path)
    case_1 = fixtures["case_1"]
    inv1 = fixtures["inv1"]

    # Simulate historical record whose binary was lost from ephemeral container filesystem
    lost_evidence = Evidence(
        id=555,
        evidence_id="EV-LOST-001",
        case_id=case_1.id,
        file_name="lost_file.pdf",
        file_type="PDF Document",
        file_size=1024,
        file_path=f"uploads/evidence/{case_1.id}/non_existent_uuid_lost_file.pdf",
        status="Active"
    )
    db.add(lost_evidence)
    db.commit()

    with pytest.raises(HTTPException) as exc_info:
        download_evidence(
            case_id=case_1.case_id,
            evidence_id="EV-LOST-001",
            current_user=inv1,
            db=db
        )
    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "Evidence file is not available in persistent storage."

    # Verify DB record was NOT deleted or altered
    refetched = db.query(Evidence).filter(Evidence.id == 555).first()
    assert refetched is not None
    assert refetched.evidence_id == "EV-LOST-001"

    print("PASS: test_5_missing_binary_returns_clear_storage_404")


def test_6_second_case_isolation(tmp_path):
    """11. Multi-case isolation: Second case upload/download operates independently."""
    import asyncio
    db, TestSession, durable_dir, fixtures = setup_test_environment(tmp_path)
    case_2 = fixtures["case_2"]
    inv2 = fixtures["inv2"]

    case_2_bytes = b"CASE_2_DISTINCT_FORENSIC_LOG_BYTES"
    case_2_hash = hashlib.sha256(case_2_bytes).hexdigest()
    test_upload = UploadFile(file=io.BytesIO(case_2_bytes), filename="case2_activity.log")

    file_data = asyncio.run(StorageService.save_uploaded_file(test_upload, case_2.id))
    new_evidence, _ = create_case_evidence(db=db, case=case_2, file_data=file_data, current_user=inv2)

    resp = download_evidence(
        case_id=case_2.case_id,
        evidence_id=new_evidence.evidence_id,
        current_user=inv2,
        db=db
    )
    assert resp.status_code == 200
    assert resp.filename == "case2_activity.log"
    assert Path(resp.path).read_bytes() == case_2_bytes
    assert hashlib.sha256(Path(resp.path).read_bytes()).hexdigest() == case_2_hash

    print("PASS: test_6_second_case_isolation")


def test_7_fresh_session_and_restart_simulation(tmp_path):
    """12. Fresh DB session and fresh service retrieval simulate container restart persistence."""
    import asyncio
    db, TestSession, durable_dir, fixtures = setup_test_environment(tmp_path)
    case_1 = fixtures["case_1"]
    inv1 = fixtures["inv1"]

    test_bytes = b"PERSISTENT_DATA_ACROSS_RESTART_SIMULATION"
    test_upload = UploadFile(file=io.BytesIO(test_bytes), filename="persistent_evidence.bin")
    file_data = asyncio.run(StorageService.save_uploaded_file(test_upload, case_1.id))
    new_evidence, _ = create_case_evidence(db=db, case=case_1, file_data=file_data, current_user=inv1)
    inv1_id = inv1.id
    ev_id_str = new_evidence.evidence_id

    # Close initial DB session completely
    db.close()

    # Simulate restart: create a brand-new DB session and new service call
    new_db_session = TestSession()
    try:
        fresh_user = new_db_session.query(User).filter(User.id == inv1_id).first()
        download_tuple = get_case_evidence_download(
            db=new_db_session,
            case_identifier="CASE-2026-001",
            evidence_identifier=ev_id_str,
            current_user=fresh_user
        )
        file_path, file_name, mime_type = download_tuple
        assert file_path.exists()
        assert file_path.read_bytes() == test_bytes
        assert file_name == "persistent_evidence.bin"
    finally:
        new_db_session.close()

    print("PASS: test_7_fresh_session_and_restart_simulation")


def test_8_path_traversal_prevention(tmp_path):
    """13. Path traversal attempts via evidence.file_path are strictly rejected."""
    db, TestSession, durable_dir, fixtures = setup_test_environment(tmp_path)
    case_1 = fixtures["case_1"]
    inv1 = fixtures["inv1"]

    traversal_evidence = Evidence(
        id=777,
        evidence_id="EV-TRAVERSAL-001",
        case_id=case_1.id,
        file_name="cmd.exe",
        file_type="Executable",
        file_size=100,
        file_path="../../windows/system32/cmd.exe",
        status="Active"
    )
    db.add(traversal_evidence)
    db.commit()

    with pytest.raises(HTTPException) as exc_info:
        download_evidence(
            case_id=case_1.case_id,
            evidence_id="EV-TRAVERSAL-001",
            current_user=inv1,
            db=db
        )
    assert exc_info.value.status_code in [403, 404]
    if exc_info.value.status_code == 404:
        assert exc_info.value.detail == "Evidence file is not available in persistent storage."
    else:
        assert "Invalid file path traversal" in exc_info.value.detail

    print("PASS: test_8_path_traversal_prevention")
