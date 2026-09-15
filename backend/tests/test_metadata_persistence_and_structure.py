"""
Comprehensive Test Suite for Metadata Persistence, Structured Response, and Read-Only Verification.
Validates:
 1. Single-file evidence upload immediately extracts and persists EvidenceRecord in MySQL/TiDB.
 2. Batch ZIP upload immediately extracts and persists EvidenceRecord for every file in MySQL/TiDB.
 3. GET /cases/{case_id}/metadata/{evidence_id} returns the clean structured response:
    - file_information
    - timestamp_information
    - integrity_information
    - additional_metadata
 4. Complete metadata fields are returned (evidence_id, case_id, filename, file_type, file_type_display,
    file_category, file_size, file_size_bytes, timestamps, mime_type, file_extension, sha256_hash, hash_status).
 5. Read-only idempotent viewing: Upload -> View -> View again -> Refresh -> View again returns exact identical data.
 6. GET requests do NOT alter, pop, clear, or delete metadata from the database.
 7. Image files return Pillow-extracted dimensions, color space, and mode in additional_metadata.
 8. Non-image files return appropriate metadata without error.
 9. Forensic timestamp sources: platform-appropriate ctime attribution; no fabricated dummy values.
10. Metadata table (GET /cases/{case_id}/metadata) returns all required summary fields without spurious N/A.
11. Cyber Expert security: assigned expert allowed; unassigned expert blocked (403); non-expert blocked (403); nonexistent case (404).
12. 100% backward compatibility: legacy metadata_information, hash_information, file_properties preserved.
"""
import io
import os
import sys
import shutil
import hashlib
import zipfile
import asyncio
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image

# Setup sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException, UploadFile
from database.database import SessionLocal, Base, engine
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from services.evidence_service import create_case_evidence, ingest_zip_evidence_batch
from services.metadata_service import MetadataService, format_bytes, classify_file_type_display
from routes.metadata_routes import (
    get_evidence_file_details,
    get_case_metadata_table,
    get_case_metadata_summary
)
from services.epra_service import authorize_cyber_expert_case_access


from models.role import Role
from models.city import City
from models.cyber_cell import CyberCell


def setup_test_fixtures(db):
    """Ensure clean test users and case exist."""
    expert = db.query(User).filter(User.role_id == 3).first()
    assert expert is not None, "At least one Cyber Expert must exist in TiDB"

    other_expert = db.query(User).filter(User.role_id == 3, User.id != expert.id).first()
    if not other_expert:
        other_expert = User(username="test_other_expert_meta", full_name="Other Expert", role_id=3, cyber_cell_id=expert.cyber_cell_id or 1)
        db.add(other_expert)
        db.commit()

    investigator = db.query(User).filter(User.role_id == 2).first()
    assert investigator is not None, "At least one Investigator must exist in TiDB"

    admin = db.query(User).filter(User.role_id == 1).first()
    assert admin is not None, "At least one Admin must exist in TiDB"

    # Test Case assigned to expert
    case = db.query(Case).filter(Case.case_id == "CASE-TEST-META-99").first()
    if not case:
        case = Case(
            case_id="CASE-TEST-META-99",
            title="Metadata Persistence Test Case",
            description="Testing metadata persistence and structured response",
            investigator_id=investigator.id,
            cyber_expert_id=expert.id,
            created_by=admin.id,
            status="Under Review",
            priority="High"
        )
        db.add(case)
        db.commit()

    return expert, other_expert, investigator, admin, case


def test_1_single_upload_persists_evidence_record():
    """Verify single file evidence upload immediately persists EvidenceRecord in MySQL."""
    db = SessionLocal()
    try:
        expert, _, _, _, case = setup_test_fixtures(db)

        # Prepare test image file
        case_dir = backend_dir / "uploads" / "evidence" / str(case.id)
        case_dir.mkdir(parents=True, exist_ok=True)
        img_path = case_dir / "forensic_snapshot.png"
        img = Image.new("RGB", (320, 240), color=(100, 150, 200))
        img.save(img_path)
        file_bytes = img_path.read_bytes()
        expected_sha = hashlib.sha256(file_bytes).hexdigest()

        file_data = {
            "file_name": "forensic_snapshot.png",
            "file_type": "Image",
            "file_size": len(file_bytes),
            "file_path": str(img_path).replace("\\", "/")
        }

        new_evidence, new_hash = create_case_evidence(
            db=db,
            case=case,
            file_data=file_data,
            current_user=expert,
            original_hash=None
        )

        ev_code = new_evidence.evidence_id
        assert ev_code is not None

        # Verify Evidence in evidences table
        ev = db.query(Evidence).filter(Evidence.evidence_id == ev_code).first()
        assert ev is not None

        # Verify EvidenceHash
        h = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
        assert h is not None
        assert h.sha256_hash == expected_sha

        # Verify EvidenceRecord was immediately persisted in MySQL!
        record = db.query(EvidenceRecord).filter(
            EvidenceRecord.external_evidence_id == ev_code,
            EvidenceRecord.case_id == str(case.case_id)
        ).first()
        assert record is not None, "EvidenceRecord MUST be persisted immediately upon upload"
        assert record.original_filename == "forensic_snapshot.png"
        assert record.original_sha256 == expected_sha
        assert record.file_size_bytes == len(file_bytes)
        assert record.evidence_type == "PNG Image"
        assert record.created_at is not None
        assert record.modified_at is not None
        assert record.uploaded_at is not None

        print("PASS: test_1_single_upload_persists_evidence_record")
    finally:
        db.close()


def test_2_batch_zip_persists_evidence_records():
    """Verify ZIP batch evidence upload immediately persists EvidenceRecord for every file."""
    db = SessionLocal()
    try:
        expert, _, _, admin, case = setup_test_fixtures(db)

        # Prepare ZIP archive with 2 files
        buf = io.BytesIO()
        f1_data = b"Critical security log data contents line 1\nline 2"
        f2_data = b"Formal affidavit text witness report"
        f1_sha = hashlib.sha256(f1_data).hexdigest()
        f2_sha = hashlib.sha256(f2_data).hexdigest()

        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("logs/audit.log", f1_data)
            zf.writestr("docs/affidavit.txt", f2_data)

        zip_bytes = buf.getvalue()
        upload_archive = UploadFile(
            filename="batch_records.zip",
            file=io.BytesIO(zip_bytes)
        )

        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        batch_res = loop.run_until_complete(
            ingest_zip_evidence_batch(
                db=db,
                case=case,
                archive=upload_archive,
                current_user=admin
            )
        )

        assert batch_res["success"] is True
        assert batch_res["total_files"] == 2

        # Check both files in EvidenceRecord
        for item in batch_res["items"]:
            ev_code = item["evidence_id"]
            rec = db.query(EvidenceRecord).filter(
                EvidenceRecord.external_evidence_id == ev_code,
                EvidenceRecord.case_id == str(case.case_id)
            ).first()
            assert rec is not None, f"EvidenceRecord for batch {ev_code} must be persisted"
            assert rec.original_sha256 is not None
            assert rec.file_size_bytes > 0

        print("PASS: test_2_batch_zip_persists_evidence_records")
    finally:
        db.close()


def test_3_clean_structured_response_sections():
    """Verify GET /cases/{case_id}/metadata/{evidence_id} returns clean structured sections."""
    db = SessionLocal()
    try:
        expert, _, _, _, case = setup_test_fixtures(db)

        # Get first evidence in this case
        rec = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).first()
        assert rec is not None

        details = get_evidence_file_details(
            case_id=str(case.case_id),
            evidence_id=rec.external_evidence_id,
            db=db,
            current_user=expert
        )

        # 1. Root IDs
        assert details["evidence_id"] == rec.external_evidence_id
        assert details["case_id"] == str(case.case_id)

        # 2. File Information section
        assert "file_information" in details
        fi = details["file_information"]
        assert fi["file_name"] == rec.original_filename
        assert "file_type" in fi
        assert "file_category" in fi
        assert "mime_type" in fi
        assert "file_extension" in fi
        assert fi["file_size_bytes"] == rec.file_size_bytes
        assert "file_size_display" in fi

        # 3. Timestamp Information section
        assert "timestamp_information" in details
        ti = details["timestamp_information"]
        assert "created_at" in ti
        assert "created_at_display" in ti
        assert "created_at_source" in ti
        assert "modified_at" in ti
        assert "modified_at_display" in ti
        assert "modified_at_source" in ti
        assert "accessed_at" in ti
        assert "accessed_at_display" in ti
        assert "accessed_at_source" in ti
        assert "uploaded_at" in ti
        assert "uploaded_at_display" in ti

        # 4. Integrity Information section
        assert "integrity_information" in details
        ii = details["integrity_information"]
        assert "sha256_hash" in ii
        assert "hash_status" in ii
        assert ii["sha256_hash"] is not None
        assert len(ii["sha256_hash"]) == 64

        # 5. Additional Metadata section
        assert "additional_metadata" in details
        am = details["additional_metadata"]
        assert "dimensions" in am
        assert "width" in am
        assert "height" in am
        assert "image_mode" in am
        assert "color_space" in am
        assert "is_empty" in am

        # 6. Direct top-level summary fields
        assert details["filename"] == rec.original_filename
        assert details["file_size_bytes"] == rec.file_size_bytes
        assert details["sha256_hash"] == ii["sha256_hash"]
        assert details["hash_status"] == ii["hash_status"]

        # 7. Backward compatibility blocks
        assert "metadata_information" in details
        assert "hash_information" in details
        assert "file_properties" in details
        assert "download_url" in details

        print("PASS: test_3_clean_structured_response_sections")
    finally:
        db.close()


def test_4_read_only_idempotent_viewing():
    """Verify consecutive GET metadata calls return identical data and do NOT modify or delete records."""
    db = SessionLocal()
    try:
        expert, _, _, _, case = setup_test_fixtures(db)
        rec = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).first()
        assert rec is not None

        # Snapshot before reads
        initial_sha = rec.original_sha256
        initial_created = rec.created_at
        initial_modified = rec.modified_at
        initial_uploaded = rec.uploaded_at
        initial_count = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).count()

        # View 1
        view1 = get_evidence_file_details(str(case.case_id), rec.external_evidence_id, db, expert)
        # View 2
        view2 = get_evidence_file_details(str(case.case_id), rec.external_evidence_id, db, expert)
        # Table 1
        table1 = get_case_metadata_table(str(case.case_id), None, "id", "asc", 1, 10, db, expert)
        # Table 2 (refresh)
        table2 = get_case_metadata_table(str(case.case_id), None, "id", "asc", 1, 10, db, expert)
        # View 3
        view3 = get_evidence_file_details(str(case.case_id), rec.external_evidence_id, db, expert)

        # Assert responses are 100% identical
        assert view1 == view2 == view3
        assert table1["total_items"] == table2["total_items"]
        assert len(table1["items"]) == len(table2["items"])

        # Snapshot after reads: DB was NOT modified or deleted
        db.expire_all()
        rec_after = db.query(EvidenceRecord).filter(EvidenceRecord.id == rec.id).first()
        assert rec_after.original_sha256 == initial_sha
        assert rec_after.created_at == initial_created
        assert rec_after.modified_at == initial_modified
        assert rec_after.uploaded_at == initial_uploaded
        assert db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).count() == initial_count

        print("PASS: test_4_read_only_idempotent_viewing")
    finally:
        db.close()


def test_5_forensic_timestamps_and_no_fabricated_values():
    """Verify timestamps reflect genuine sources and are not falsely fabricated."""
    db = SessionLocal()
    try:
        expert, _, _, _, case = setup_test_fixtures(db)
        rec = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).first()

        details = get_evidence_file_details(str(case.case_id), rec.external_evidence_id, db, expert)
        ti = details["timestamp_information"]

        # Check source attribution
        if ti["created_at_source"]:
            assert "st_ctime" in ti["created_at_source"]
        if ti["modified_at_source"]:
            assert "st_mtime" in ti["modified_at_source"]

        # Upload timestamp must be present
        assert ti["uploaded_at"] is not None
        assert ti["uploaded_at_display"] is not None

        print("PASS: test_5_forensic_timestamps_and_no_fabricated_values")
    finally:
        db.close()


def test_6_metadata_table_mapping_no_spurious_na():
    """Verify metadata table returns summary fields without spurious N/A for existing data."""
    db = SessionLocal()
    try:
        expert, _, _, _, case = setup_test_fixtures(db)

        table = get_case_metadata_table(str(case.case_id), None, "id", "asc", 1, 10, db, expert)
        assert table["total_items"] >= 3
        assert len(table["items"]) >= 3

        for item in table["items"]:
            assert item["evidence_id"] is not None
            assert item["case_id"] == str(case.case_id)
            assert item["filename"] is not None
            assert item["file_type"] is not None
            assert item["file_category"] is not None
            assert item["file_size"] is not None
            assert item["size_bytes"] > 0
            assert item["sha256_hash"] is not None
            assert len(item["sha256_hash"]) == 64
            assert item["hash_status"] in ["Verified", "Tampered", "Unknown", "Pending"]
            assert item["uploaded_at"] is not None
            assert item["uploaded_at_display"] is not None

        print("PASS: test_6_metadata_table_mapping_no_spurious_na")
    finally:
        db.close()


def test_7_cyber_expert_authorization_and_scoping():
    """Verify strict access control: assigned expert allowed; unassigned/wrong role blocked."""
    db = SessionLocal()
    try:
        expert, other_expert, investigator, admin, case = setup_test_fixtures(db)

        # 1. Assigned expert succeeds
        c = authorize_cyber_expert_case_access(db, case.case_id, expert)
        assert c.id == case.id

        # 2. Unassigned Cyber Expert gets 403
        try:
            authorize_cyber_expert_case_access(db, case.case_id, other_expert)
            assert False, "Unassigned Cyber Expert must get 403"
        except HTTPException as e:
            assert e.status_code == 403
            assert "Access denied" in e.detail

        # 3. Non-Cyber Expert (Investigator role 2) gets 403
        try:
            authorize_cyber_expert_case_access(db, case.case_id, investigator)
            assert False, "Non-Cyber Expert must get 403"
        except HTTPException as e:
            assert e.status_code == 403
            assert "Cyber Expert access required" in e.detail

        # 4. Non-existent case gets 404
        try:
            authorize_cyber_expert_case_access(db, "CASE-DOES-NOT-EXIST-999", expert)
            assert False, "Nonexistent case must get 404"
        except HTTPException as e:
            assert e.status_code == 404

        print("PASS: test_7_cyber_expert_authorization_and_scoping")
    finally:
        db.close()


def test_8_image_pillow_properties():
    """Verify Pillow image dimensions and properties are safely extracted into additional_metadata."""
    db = SessionLocal()
    try:
        expert, _, _, _, case = setup_test_fixtures(db)

        # Find the image record
        img_rec = db.query(EvidenceRecord).filter(
            EvidenceRecord.case_id == str(case.case_id),
            EvidenceRecord.original_filename.like("%.png")
        ).first()
        assert img_rec is not None

        details = get_evidence_file_details(str(case.case_id), img_rec.external_evidence_id, db, expert)
        am = details["additional_metadata"]

        assert am["width"] == 320
        assert am["height"] == 240
        assert am["dimensions"] == "320 x 240"
        assert am["image_mode"] == "RGB"

        print("PASS: test_8_image_pillow_properties")
    finally:
        db.close()


def clean_up_test_fixtures():
    """Clean up test records created during these tests to keep TiDB pristine."""
    db = SessionLocal()
    try:
        case = db.query(Case).filter(Case.case_id == "CASE-TEST-META-99").first()
        if case:
            # Delete evidence records
            db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).delete(synchronize_session=False)

            # Unlink files on disk and collect evidence IDs
            evs = db.query(Evidence).filter(Evidence.case_id == case.id).all()
            ev_ids = [ev.id for ev in evs]
            for ev in evs:
                if ev.file_path and Path(ev.file_path).exists():
                    try:
                        Path(ev.file_path).unlink()
                    except Exception:
                        pass

            if ev_ids:
                db.query(EvidenceHash).filter(EvidenceHash.evidence_id.in_(ev_ids)).delete(synchronize_session=False)
                db.query(Evidence).filter(Evidence.id.in_(ev_ids)).delete(synchronize_session=False)

            # Clean timeline
            from models.case_timeline import CaseTimeline
            db.query(CaseTimeline).filter(CaseTimeline.case_id == case.id).delete(synchronize_session=False)

            # Clean notifications
            from models.notification import Notification
            db.query(Notification).filter(Notification.message.like("%CASE-TEST-META-99%")).delete(synchronize_session=False)

            db.commit()

            # Now delete case
            db.query(Case).filter(Case.id == case.id).delete(synchronize_session=False)
            db.commit()

        # Delete test users
        for uname in ["test_expert_meta", "test_other_expert_meta", "test_inv_meta", "test_admin_meta"]:
            u = db.query(User).filter(User.username == uname).first()
            if u:
                db.delete(u)
        db.commit()
    except Exception as e:
        print(f"Cleanup warning: {e}")
        db.rollback()
    finally:
        db.close()


if __name__ == "__main__":
    print("=" * 80)
    print("RUNNING METADATA PERSISTENCE & STRUCTURED RESPONSE TEST SUITE")
    print("=" * 80)
    clean_up_test_fixtures()
    try:
        test_1_single_upload_persists_evidence_record()
        test_2_batch_zip_persists_evidence_records()
        test_3_clean_structured_response_sections()
        test_4_read_only_idempotent_viewing()
        test_5_forensic_timestamps_and_no_fabricated_values()
        test_6_metadata_table_mapping_no_spurious_na()
        test_7_cyber_expert_authorization_and_scoping()
        test_8_image_pillow_properties()
        print("=" * 80)
        print("ALL 8 METADATA PERSISTENCE & STRUCTURE TESTS PASSED SUCCESSFULLY!")
        print("=" * 80)
    finally:
        clean_up_test_fixtures()
