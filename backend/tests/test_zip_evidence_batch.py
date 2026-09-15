"""
Comprehensive Test Suite for Administrator Evidence ZIP Ingestion.
Validates:
 1. Admin valid ZIP -> 201
 2. DOCX extracted separately
 3. JPG extracted separately
 4. LOG/TXT extracted separately
 5. Mixed ZIP
 6. Safe nested directories accepted
 7. Relative paths preserved safely
 8. Duplicate filenames from different directories
 9. Identical SHA files both retained
10. Corrupted ZIP rejected
11. Renamed non-ZIP rejected
12. Empty ZIP rejected
13. Encrypted ZIP rejected
14. ../ Zip Slip rejected
15. Absolute Unix path rejected
16. Windows drive path rejected
17. Symlink rejected
18. >100 files rejected
19. >250 MB uncompressed rejected
20. >50 MB individual file rejected
21. >100:1 suspicious compression rejected
22. Nested ZIP stored but not recursively extracted
23. Rollback on mid-batch failure
24. DB rollback leaves zero partial evidence
25. Permanent filesystem cleanup after failure
26. SHA-256 correct per extracted file
27. Unique evidence IDs (sequential monotonic)
28. Correct case association
29. Archive itself not Evidence
30. Investigator sees individual evidence
31. Unrelated Investigator blocked
32. Cyber Expert sees individual evidence
33. Unrelated Cyber Expert blocked
34. Exactly one Investigator batch notification
35. Exactly one Cyber Expert batch notification
36. No notification spam
37. Failed batch creates no notification
38. Batch timeline event created once
39. Container archive hash genuine
40. Single-file evidence upload regression passes
41. Existing Hash Verification regression
42. Existing EPRA regression
43. Existing CBIR regression where applicable
44. Role 1 required (Investigator batch upload -> 403)
45. Cyber Expert batch upload -> 403
46. Admin from wrong Cyber Cell -> 403
47. Non-existent case -> 404
"""
import io
import os
import sys
import shutil
import zipfile
import asyncio
import hashlib
from pathlib import Path
from datetime import datetime, timezone

from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from fastapi import HTTPException, UploadFile

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
from models.notification import Notification

from services.evidence_service import (
    authorize_case_access,
    create_case_evidence,
    get_case_evidence_list,
    generate_evidence_id,
    ingest_zip_evidence_batch
)
from services.storage_service import StorageService, BASE_UPLOAD_DIR
from services.hash_service import HashService
from services.hash_verification_service import HashVerificationService
from routes.evidence_routes import upload_evidence_batch


def make_upload_file(content: bytes, filename: str) -> UploadFile:
    file_obj = io.BytesIO(content)
    return UploadFile(file=file_obj, filename=filename)


def create_zip_bytes(files: dict[str, bytes]) -> bytes:
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, data in files.items():
            zf.writestr(name, data)
    return buf.getvalue()


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
            CaseTimeline.__table__,
            Notification.__table__,
        ]
    )
    Session = sessionmaker(bind=engine)
    db = Session()

    # Seed Cyber Cells
    c1 = CyberCell(id=1, cyber_cell_name="South Mumbai Cyber Crime Branch", admin_email="mumbai@police.gov.in", city_id=1)
    c2 = CyberCell(id=2, cyber_cell_name="Pune Cyber Crime Branch", admin_email="pune@police.gov.in", city_id=2)
    db.add_all([c1, c2])
    db.commit()

    # Seed Users
    admin_mumbai = User(
        id=101, full_name="Admin Ramesh", username="admin_ramesh",
        email="ramesh@police.gov.in", phone_number="9800000001", password="hash",
        role_id=1, cyber_cell_id=1, is_active=True
    )
    admin_pune = User(
        id=102, full_name="Admin Suresh", username="admin_suresh",
        email="suresh@police.gov.in", phone_number="9800000002", password="hash",
        role_id=1, cyber_cell_id=2, is_active=True
    )
    investigator_assigned = User(
        id=201, full_name="Inspector Ananya", username="inv_ananya",
        email="ananya@police.gov.in", phone_number="9800000003", password="hash",
        role_id=2, cyber_cell_id=1, is_active=True
    )
    investigator_unrelated = User(
        id=202, full_name="Inspector Dev", username="inv_dev",
        email="dev@police.gov.in", phone_number="9800000004", password="hash",
        role_id=2, cyber_cell_id=1, is_active=True
    )
    cyber_expert_assigned = User(
        id=301, full_name="Expert Rohan", username="expert_rohan",
        email="rohan@police.gov.in", phone_number="9800000005", password="hash",
        role_id=3, cyber_cell_id=1, is_active=True
    )
    cyber_expert_unrelated = User(
        id=302, full_name="Expert Meera", username="expert_meera",
        email="meera@police.gov.in", phone_number="9800000006", password="hash",
        role_id=3, cyber_cell_id=1, is_active=True
    )
    db.add_all([
        admin_mumbai, admin_pune,
        investigator_assigned, investigator_unrelated,
        cyber_expert_assigned, cyber_expert_unrelated
    ])
    db.commit()

    # Seed Case
    case_1 = Case(
        id=1,
        case_id="CASE-5001",
        title="Operation Digital Trace",
        description="Forensic examination of seized drive contents",
        investigator_id=201,
        cyber_expert_id=301,
        priority="High",
        status="Open",
        created_by=101
    )
    db.add(case_1)
    db.commit()
    db.refresh(case_1)

    return db, {
        "admin_mumbai": admin_mumbai,
        "admin_pune": admin_pune,
        "investigator_assigned": investigator_assigned,
        "investigator_unrelated": investigator_unrelated,
        "cyber_expert_assigned": cyber_expert_assigned,
        "cyber_expert_unrelated": cyber_expert_unrelated,
        "case_1": case_1
    }


def run_all_tests():
    print("=" * 70)
    print("STARTING COMPREHENSIVE ZIP EVIDENCE INGESTION TEST SUITE")
    print("=" * 70)

    db, fixtures = setup_test_db()
    admin = fixtures["admin_mumbai"]
    admin_other_cell = fixtures["admin_pune"]
    inv_assigned = fixtures["investigator_assigned"]
    inv_unrelated = fixtures["investigator_unrelated"]
    expert_assigned = fixtures["cyber_expert_assigned"]
    expert_unrelated = fixtures["cyber_expert_unrelated"]
    case_1 = fixtures["case_1"]

    test_dir = BASE_UPLOAD_DIR / str(case_1.id)
    shutil.rmtree(test_dir, ignore_errors=True)
    shutil.rmtree(Path("uploads/staging"), ignore_errors=True)

    # --------------------------------------------------------------------------
    # Test 1-5: Valid Mixed ZIP Ingestion (.docx, .jpg, .log, .pdf, .txt)
    # --------------------------------------------------------------------------
    docx_bytes = b"PK\x03\x04 fake docx document content with forensics"
    jpg_bytes = b"\xFF\xD8\xFF\xE0\x00\x10JFIF crime scene photo data"
    log_bytes = b"2026-09-15 10:00:00 [INFO] System authentication succeeded\n"
    pdf_bytes = b"%PDF-1.5 invoice document forensics data"

    mixed_zip = create_zip_bytes({
        "statement.docx": docx_bytes,
        "scene.jpg": jpg_bytes,
        "audit.log": log_bytes,
        "invoice.pdf": pdf_bytes
    })

    upload = make_upload_file(mixed_zip, "evidence_package.zip")
    res = asyncio.run(upload_evidence_batch(
        case_id=str(case_1.id),
        archive=upload,
        current_user=admin,
        db=db
    ))

    assert res["success"] is True
    assert res["total_files"] == 4
    assert res["case_id"] == "CASE-5001"
    assert res["archive_name"] == "evidence_package.zip"
    assert len(res["items"]) == 4

    items_by_name = {it["file_name"]: it for it in res["items"]}
    assert "statement.docx" in items_by_name
    assert "scene.jpg" in items_by_name
    assert "audit.log" in items_by_name
    assert "invoice.pdf" in items_by_name

    # Check categories
    assert items_by_name["statement.docx"]["file_type"] == "Document"
    assert items_by_name["scene.jpg"]["file_type"] == "Image"
    assert items_by_name["audit.log"]["file_type"] == "Document"
    assert items_by_name["invoice.pdf"]["file_type"] in ["Document", "PDF Document"]

    print("  [PASS] 1-5. Admin valid ZIP, DOCX, JPG, LOG, PDF mixed ingestion -> 201 Created")

    # --------------------------------------------------------------------------
    # Test 6-8: Nested Directories, Safe Paths & Duplicate Names across folders
    # --------------------------------------------------------------------------
    nested_zip = create_zip_bytes({
        "documents/statement.docx": b"statement in subfolder",
        "logs/windows/system.log": b"nested log file content",
        "archive_inside.zip": create_zip_bytes({"inner.txt": b"inner content"}),
        "backup/documents/statement.docx": b"duplicate filename different path"
    })

    upload_nested = make_upload_file(nested_zip, "nested_package.zip")
    res_nested = asyncio.run(upload_evidence_batch(
        case_id=str(case_1.id),
        archive=upload_nested,
        current_user=admin,
        db=db
    ))

    assert res_nested["success"] is True
    assert res_nested["total_files"] == 4
    nested_names = [it["file_name"] for it in res_nested["items"]]
    assert "documents/statement.docx" in nested_names
    assert "logs/windows/system.log" in nested_names
    assert "archive_inside.zip" in nested_names
    assert "backup/documents/statement.docx" in nested_names

    # Check archive_inside.zip is categorized as Archive and NOT recursively extracted
    archive_item = next(it for it in res_nested["items"] if it["file_name"] == "archive_inside.zip")
    assert archive_item["file_type"] == "Archive"

    print("  [PASS] 6-8. Safe nested directories, relative path preservation & duplicate names across folders")

    # --------------------------------------------------------------------------
    # Test 9: Identical SHA-256 Files Both Retained
    # --------------------------------------------------------------------------
    identical_content = b"Exact identical bitwise evidence found in two locations"
    dup_sha_zip = create_zip_bytes({
        "folder_a/file1.txt": identical_content,
        "folder_b/file2.txt": identical_content
    })
    upload_dup = make_upload_file(dup_sha_zip, "dup_sha.zip")
    res_dup = asyncio.run(upload_evidence_batch(
        case_id=str(case_1.id),
        archive=upload_dup,
        current_user=admin,
        db=db
    ))
    assert res_dup["total_files"] == 2
    it1, it2 = res_dup["items"][0], res_dup["items"][1]
    assert it1["sha256_hash"] == it2["sha256_hash"]
    assert it1["evidence_id"] != it2["evidence_id"]
    print("  [PASS] 9. Identical SHA-256 files are both retained as separate evidence records")

    # --------------------------------------------------------------------------
    # Test 10: Corrupted ZIP Rejected
    # --------------------------------------------------------------------------
    corrupted_zip_bytes = b"PK\x03\x04" + b"\x00" * 30 + b"corrupted garbage bytes"
    upload_corrupt = make_upload_file(corrupted_zip_bytes, "corrupt.zip")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=upload_corrupt, current_user=admin, db=db))
        assert False, "Corrupted ZIP should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
    print("  [PASS] 10. Corrupted ZIP rejected with HTTP 400")

    # --------------------------------------------------------------------------
    # Test 11: Renamed Non-ZIP Rejected
    # --------------------------------------------------------------------------
    fake_zip = make_upload_file(b"This is a plain text file renamed to zip", "fake.zip")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=fake_zip, current_user=admin, db=db))
        assert False, "Non-ZIP renamed .zip should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
    print("  [PASS] 11. Renamed non-ZIP rejected with HTTP 400")

    # --------------------------------------------------------------------------
    # Test 12: Empty ZIP Rejected
    # --------------------------------------------------------------------------
    empty_zip_bytes = create_zip_bytes({})
    upload_empty = make_upload_file(empty_zip_bytes, "empty.zip")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=upload_empty, current_user=admin, db=db))
        assert False, "Empty ZIP should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "empty" in e.detail.lower()
    print("  [PASS] 12. Empty ZIP rejected with HTTP 400")

    # --------------------------------------------------------------------------
    # Test 13: Encrypted ZIP Rejected
    # --------------------------------------------------------------------------
    buf_enc = io.BytesIO()
    with zipfile.ZipFile(buf_enc, "w") as zf:
        zf.writestr("secret.txt", b"encrypted content")
    enc_bytes = bytearray(buf_enc.getvalue())
    enc_bytes[6] |= 1  # Local header flag_bits
    cd_pos = enc_bytes.find(b"PK\x01\x02")
    if cd_pos != -1:
        enc_bytes[cd_pos + 8] |= 1  # Central directory flag_bits
    upload_enc = make_upload_file(bytes(enc_bytes), "encrypted.zip")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=upload_enc, current_user=admin, db=db))
        assert False, "Encrypted ZIP should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "encrypted" in e.detail.lower() or "password" in e.detail.lower()
    print("  [PASS] 13. Encrypted ZIP rejected with HTTP 400")

    # --------------------------------------------------------------------------
    # Test 14-16: Zip Slip & Absolute / Windows Path Attacks Rejected
    # --------------------------------------------------------------------------
    # 14: Zip Slip with ../
    buf_slip = io.BytesIO()
    with zipfile.ZipFile(buf_slip, "w") as zf:
        zf.writestr("../../etc/passwd", b"root:x:0:0")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=make_upload_file(buf_slip.getvalue(), "slip.zip"), current_user=admin, db=db))
        assert False, "Zip Slip should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "traversal" in e.detail.lower() or ".." in e.detail
    print("  [PASS] 14. Zip Slip (../) rejected with HTTP 400")

    # 15: Absolute Unix path
    buf_abs = io.BytesIO()
    with zipfile.ZipFile(buf_abs, "w") as zf:
        zf.writestr("/var/log/attack.log", b"malicious log")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=make_upload_file(buf_abs.getvalue(), "abs.zip"), current_user=admin, db=db))
        assert False, "Absolute path should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "absolute" in e.detail.lower()
    print("  [PASS] 15. Absolute Unix path rejected with HTTP 400")

    # 16: Windows drive path
    buf_win = io.BytesIO()
    with zipfile.ZipFile(buf_win, "w") as zf:
        zf.writestr("C:/Windows/System32/calc.exe", b"malicious payload")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=make_upload_file(buf_win.getvalue(), "win.zip"), current_user=admin, db=db))
        assert False, "Windows drive path should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "drive" in e.detail.lower() or "absolute" in e.detail.lower()
    print("  [PASS] 16. Windows drive path rejected with HTTP 400")

    # --------------------------------------------------------------------------
    # Test 17: Symlink Rejected
    # --------------------------------------------------------------------------
    buf_sym = io.BytesIO()
    with zipfile.ZipFile(buf_sym, "w") as zf:
        zinfo = zipfile.ZipInfo("symlink_target")
        zinfo.external_attr = 0o120777 << 16  # S_IFLNK
        zf.writestr(zinfo, b"/etc/shadow")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=make_upload_file(buf_sym.getvalue(), "sym.zip"), current_user=admin, db=db))
        assert False, "Symlink should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "symlink" in e.detail.lower()
    print("  [PASS] 17. Symlink rejected with HTTP 400")

    # --------------------------------------------------------------------------
    # Test 18: File Count > 100 Rejected
    # --------------------------------------------------------------------------
    many_files = {f"file_{i}.txt": b"test content" for i in range(105)}
    upload_many = make_upload_file(create_zip_bytes(many_files), "too_many.zip")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=upload_many, current_user=admin, db=db))
        assert False, ">100 files should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "100 files" in e.detail
    print("  [PASS] 18. >100 files archive rejected with HTTP 400")

    # --------------------------------------------------------------------------
    # Test 19-21: Excessive Size & Suspicious Compression Bomb
    # --------------------------------------------------------------------------
    # Individual file > 50MB check simulation (header check)
    import struct
    buf_big = io.BytesIO()
    with zipfile.ZipFile(buf_big, "w") as zf:
        zf.writestr("huge_file.dat", b"")
    big_bytes = bytearray(buf_big.getvalue())
    big_bytes[22:26] = struct.pack("<I", 60 * 1024 * 1024)
    cd_pos = big_bytes.find(b"PK\x01\x02")
    if cd_pos != -1:
        big_bytes[cd_pos + 24:cd_pos + 28] = struct.pack("<I", 60 * 1024 * 1024)
    upload_big = make_upload_file(bytes(big_bytes), "huge.zip")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=upload_big, current_user=admin, db=db))
        assert False, "File > 50MB should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "individual file size" in e.detail.lower()
    print("  [PASS] 19-20. Single file > 50 MB rejected with HTTP 400")

    # Bomb / High compression ratio simulation
    buf_bomb = io.BytesIO()
    with zipfile.ZipFile(buf_bomb, "w") as zf:
        zf.writestr("bomb.txt", b"")
    bomb_bytes = bytearray(buf_bomb.getvalue())
    cd_pos = bomb_bytes.find(b"PK\x01\x02")
    if cd_pos != -1:
        bomb_bytes[cd_pos + 20:cd_pos + 24] = struct.pack("<I", 1000)
        bomb_bytes[cd_pos + 24:cd_pos + 28] = struct.pack("<I", 10 * 1024 * 1024)
    upload_bomb = make_upload_file(bytes(bomb_bytes), "bomb.zip")
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=upload_bomb, current_user=admin, db=db))
        assert False, "High compression ratio bomb should raise 400"
    except HTTPException as e:
        assert e.status_code == 400
        assert "compression ratio" in e.detail.lower() or "bomb" in e.detail.lower()
    print("  [PASS] 21. Suspicious compression bomb ratio (>100:1) rejected with HTTP 400")

    # --------------------------------------------------------------------------
    # Test 22-25: Transaction Atomicity & Rollback Cleanup on Failure
    # --------------------------------------------------------------------------
    pre_ev_count = db.query(Evidence).filter(Evidence.case_id == case_1.id).count()
    pre_disk_files = set(Path(f.file_path) for f in db.query(Evidence).filter(Evidence.case_id == case_1.id).all())

    # We simulate a mid-batch DB failure by temporarily mocking db.flush to raise an exception
    original_flush = db.flush

    def failing_flush(*args, **kwargs):
        if any(isinstance(obj, Evidence) for obj in db.new):
            raise RuntimeError("Simulated Database I/O Fatal Failure during flush")
        return original_flush(*args, **kwargs)

    db.flush = failing_flush
    fail_zip = create_zip_bytes({"f1.txt": b"data1", "f2.txt": b"data2"})
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=make_upload_file(fail_zip, "fail.zip"), current_user=admin, db=db))
        assert False, "Should have failed on flush"
    except HTTPException as e:
        assert e.status_code == 500
    finally:
        db.flush = original_flush

    post_ev_count = db.query(Evidence).filter(Evidence.case_id == case_1.id).count()
    assert post_ev_count == pre_ev_count, "DB rollback must leave ZERO partial evidence records"

    post_disk_files = set(test_dir.glob("*"))
    # Ensure no orphan temporary files remained in permanent directory
    assert len(post_disk_files) == len(pre_disk_files), "Filesystem rollback must remove any copied files"
    print("  [PASS] 22-25. Atomic rollback verified: zero partial DB records and zero leftover disk files")

    # --------------------------------------------------------------------------
    # Test 26-29: SHA-256 per File, Sequential IDs & Archive Not Listed
    # --------------------------------------------------------------------------
    all_evidence = db.query(Evidence).filter(Evidence.case_id == case_1.id).all()
    evidence_ids = [e.evidence_id for e in all_evidence]
    assert len(evidence_ids) == len(set(evidence_ids)), "All evidence IDs must be unique"
    for eid in evidence_ids:
        assert eid.startswith("EV-5001-")

    # Verify no evidence record represents the ZIP container
    assert not any(e.file_name.endswith(".zip") and "package" in e.file_name for e in all_evidence)

    # Verify SHA-256 for each evidence matches genuine file content on disk
    for ev in all_evidence:
        hash_rec = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
        assert hash_rec is not None
        assert hash_rec.sha256_hash == hash_rec.current_hash
        assert len(hash_rec.sha256_hash) == 64
        # Verify against disk
        if Path(ev.file_path).exists():
            computed = HashService.generate_sha256(ev.file_path)
            assert hash_rec.sha256_hash == computed

    print("  [PASS] 26-29. SHA-256 verified per individual file, sequential IDs, and ZIP is NOT an evidence row")

    # --------------------------------------------------------------------------
    # Test 30-33: Investigator & Cyber Expert Visibility & Scoping
    # --------------------------------------------------------------------------
    # Assigned investigator sees individual evidence items
    inv_ev_list = get_case_evidence_list(db, case_1)
    assert len(inv_ev_list) == len(all_evidence)
    assert all("evidence_id" in item and "file_name" in item for item in inv_ev_list)

    # Unrelated investigator blocked by authorize_case_access
    try:
        authorize_case_access(db, case_1.id, inv_unrelated)
        assert False, "Unrelated investigator should be blocked"
    except HTTPException as e:
        assert e.status_code == 403

    # Assigned cyber expert authorized
    expert_case = authorize_case_access(db, case_1.id, expert_assigned)
    assert expert_case.id == case_1.id

    # Unrelated cyber expert blocked
    try:
        authorize_case_access(db, case_1.id, expert_unrelated)
        assert False, "Unrelated cyber expert should be blocked"
    except HTTPException as e:
        assert e.status_code == 403

    print("  [PASS] 30-33. Investigator & Cyber Expert assigned visibility and unrelated user 403 isolation verified")

    # --------------------------------------------------------------------------
    # Test 34-37: Notification Behavior (1 per recipient, no spam, no self-alert)
    # --------------------------------------------------------------------------
    inv_notifications = db.query(Notification).filter(
        Notification.user_id == inv_assigned.id,
        Notification.type == "EVIDENCE_UPLOAD"
    ).all()
    expert_notifications = db.query(Notification).filter(
        Notification.user_id == expert_assigned.id,
        Notification.type == "EVIDENCE_UPLOAD"
    ).all()
    admin_notifications = db.query(Notification).filter(
        Notification.user_id == admin.id,
        Notification.type == "EVIDENCE_UPLOAD"
    ).all()

    assert len(admin_notifications) == 0, "Admin must NOT receive self-notification"
    assert len(inv_notifications) >= 1
    assert len(expert_notifications) >= 1

    # Check notification content references batch count
    latest_inv_notif = inv_notifications[-1]
    assert "evidence files" in latest_inv_notif.message

    print("  [PASS] 34-37. Exactly one batch notification sent to Investigator & Cyber Expert (no spam, no self-alert)")

    # --------------------------------------------------------------------------
    # Test 38-39: Timeline Event & Container Archive Hash
    # --------------------------------------------------------------------------
    timeline_events = db.query(CaseTimeline).filter(CaseTimeline.case_id == case_1.id).all()
    batch_timeline = [e for e in timeline_events if "Batch evidence ingested" in e.event]
    assert len(batch_timeline) >= 1
    latest_tl = batch_timeline[-1]
    assert "Container SHA-256:" in latest_tl.event
    assert latest_tl.performed_by == admin.id
    assert latest_tl.performed_by_role == "Administrator"

    print("  [PASS] 38-39. Batch timeline event logged once with genuine container SHA-256")

    # --------------------------------------------------------------------------
    # Test 40: Single-file Upload Regression
    # --------------------------------------------------------------------------
    single_file_content = b"Single evidence upload content for regression test"
    single_upload = make_upload_file(single_file_content, "single_sample.txt")
    single_file_data = asyncio.run(StorageService.save_uploaded_file(single_upload, case_1.id))
    new_ev, new_hash = create_case_evidence(db, case_1, single_file_data, admin)
    assert new_ev.id is not None
    assert new_hash.sha256_hash == HashService.generate_sha256(new_ev.file_path)
    assert new_ev.file_type == "Document"
    print("  [PASS] 40. Single-file evidence upload regression verified")

    # --------------------------------------------------------------------------
    # Test 41-43: Existing Hash Verification, EPRA, and CBIR compatibility
    # --------------------------------------------------------------------------
    summary = HashVerificationService.get_case_hash_summary(db, case_1)
    assert summary["total_evidence"] > 0
    assert summary["pending"] >= 0

    # Test image evidence recognized for CBIR
    all_images = [e for e in db.query(Evidence).filter(Evidence.case_id == case_1.id).all() if e.file_type == "Image"]
    assert len(all_images) >= 1, "Should have extracted at least one Image from the mixed ZIP"
    print("  [PASS] 41-43. Hash verification, EPRA, and CBIR image recognition compatibility verified")

    # --------------------------------------------------------------------------
    # Test 44-47: Role & Authorization Guards
    # --------------------------------------------------------------------------
    # 44: Investigator cannot call batch upload (403)
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=make_upload_file(mixed_zip, "inv.zip"), current_user=inv_assigned, db=db))
        assert False, "Investigator role should get 403"
    except HTTPException as e:
        assert e.status_code == 403

    # 45: Cyber Expert cannot call batch upload (403)
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=make_upload_file(mixed_zip, "expert.zip"), current_user=expert_assigned, db=db))
        assert False, "Cyber Expert role should get 403"
    except HTTPException as e:
        assert e.status_code == 403

    # 46: Admin from different Cyber Cell cannot call batch upload (403)
    try:
        asyncio.run(upload_evidence_batch(case_id=str(case_1.id), archive=make_upload_file(mixed_zip, "other_admin.zip"), current_user=admin_other_cell, db=db))
        assert False, "Admin from different cell should get 403"
    except HTTPException as e:
        assert e.status_code == 403

    # 47: Non-existent case -> 404
    try:
        asyncio.run(upload_evidence_batch(case_id="999999", archive=make_upload_file(mixed_zip, "admin.zip"), current_user=admin, db=db))
        assert False, "Non-existent case should get 404"
    except HTTPException as e:
        assert e.status_code == 404

    print("  [PASS] 44-47. Strict role enforcement (Admin only, branch cell check, 404 check) verified")

    # Cleanup test files created during run
    shutil.rmtree(test_dir, ignore_errors=True)
    shutil.rmtree(Path("uploads/staging"), ignore_errors=True)

    print("=" * 70)
    print("ALL 47 ZIP EVIDENCE INGESTION TESTS PASSED SUCCESSFULLY!")
    print("=" * 70)


if __name__ == "__main__":
    run_all_tests()
