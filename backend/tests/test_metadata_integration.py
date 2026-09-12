import os
import sys
import subprocess
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image

# Add project root and backend dir to sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException
from database.database import SessionLocal, engine, Base
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord

from services.evidence_classifier import EvidenceClassifier
from services.evidence_validation_service import EvidenceValidationService
from services.backend_adapter import (
    get_backend_adapter,
    set_backend_adapter,
    LiveBackendAdapter,
    MockBackendProvider,
    CaseData,
    EvidenceItem,
    map_backend_verification_status
)
from services.metadata_service import (
    MetadataService,
    format_bytes,
    classify_file_type_display
)
from services.epra_service import authorize_cyber_expert_case_access
from routes.metadata_routes import router as metadata_router


def test_1_deepak_core_services_and_classification():
    """Verify EvidenceClassifier, EvidenceValidationService, format_bytes, and status mapping."""
    # 1. format_bytes
    assert format_bytes(0) == "0 B"
    assert format_bytes(512) == "512 B"
    assert format_bytes(2048) == "2.0 KB"
    assert "MB" in format_bytes(5 * 1024 * 1024)
    assert "GB" in format_bytes(2 * 1024 * 1024 * 1024)

    # 2. classify_file_type_display
    cat, disp = classify_file_type_display("photo.jpg")
    assert cat == "IMAGE" and disp == "JPEG Image"

    cat, disp = classify_file_type_display("doc.pdf")
    assert cat == "PDF" and disp == "PDF Document"

    cat, disp = classify_file_type_display("report.xlsx")
    assert cat == "SPREADSHEET" and disp == "Excel Document"

    cat, disp = classify_file_type_display("unknown.xyz")
    assert cat == "OTHER" and disp == "Data File"

    # 3. map_backend_verification_status
    assert map_backend_verification_status("Verified") == "Verified"
    assert map_backend_verification_status("match") == "Verified"
    assert map_backend_verification_status("Tampered") == "Tampered"
    assert map_backend_verification_status("mismatch") == "Tampered"
    assert map_backend_verification_status("in_progress") == "Pending"
    assert map_backend_verification_status(None) == "Unknown"

    # 4. EvidenceValidationService
    missing = EvidenceValidationService.validate_file("nonexistent_path_xyz.bin")
    assert missing["valid"] is False
    assert missing["status"] == "FILE_NOT_FOUND"

    print("PASS: test_1_deepak_core_services_and_classification")


def test_2_deepak_standalone_extract_metadata(tmp_path=None):
    """Verify Deepak's MetadataService.extract_metadata on image and non-image files."""
    test_dir = backend_dir / "uploads" / "test_temp"
    test_dir.mkdir(parents=True, exist_ok=True)

    # 1. Non-image file
    txt_file = test_dir / "sample_notes.txt"
    txt_file.write_text("Case inspection notes content.", encoding="utf-8")

    meta_txt = MetadataService.extract_metadata(str(txt_file))
    assert meta_txt["file_name"] == "sample_notes.txt"
    assert meta_txt["file_extension"] == ".txt"
    assert meta_txt["file_size_bytes"] == txt_file.stat().st_size
    assert "filesystem_ctime" in meta_txt
    assert "filesystem_ctime_source" in meta_txt
    assert "filesystem_mtime" in meta_txt
    assert "filesystem_mtime_source" in meta_txt
    assert meta_txt["is_empty"] is False

    # 2. Image file with Pillow dimensions
    img_file = test_dir / "sample_camera.png"
    img = Image.new("RGB", (800, 600), color=(100, 150, 200))
    img.save(img_file)

    meta_img = MetadataService.extract_metadata(str(img_file))
    assert meta_img["file_name"] == "sample_camera.png"
    assert meta_img["width"] == 800
    assert meta_img["height"] == 600
    assert meta_img["dimensions"] == "800 x 600"
    assert meta_img["image_mode"] == "RGB"

    print("PASS: test_2_deepak_standalone_extract_metadata")


def test_3_routes_registered_and_endpoints_correct():
    """Verify all case-scoped metadata extraction routes are mounted."""
    routes = {r.path: r.methods for r in metadata_router.routes}
    assert "/cases/{case_id}/metadata/extract" in routes
    assert "POST" in routes["/cases/{case_id}/metadata/extract"]

    assert "/cases/{case_id}/metadata" in routes
    assert "GET" in routes["/cases/{case_id}/metadata"]

    assert "/cases/{case_id}/metadata/summary" in routes
    assert "GET" in routes["/cases/{case_id}/metadata/summary"]

    assert "/cases/{case_id}/metadata/{evidence_id}" in routes
    assert "GET" in routes["/cases/{case_id}/metadata/{evidence_id}"]

    assert "/cases/{case_id}/metadata/{evidence_id}/download" in routes
    assert "/cases/{case_id}/metadata/{evidence_id}/preview" in routes

    print("PASS: test_3_routes_registered_and_endpoints_correct")


def test_4_cyber_expert_authorization_and_case_scoping():
    """Verify role_id == 3 and case assignment security."""
    db = SessionLocal()
    try:
        # Non-cyber expert role -> 403
        fake_user = User(id=6601, role_id=2, full_name="Investigator Only")
        try:
            authorize_cyber_expert_case_access(db, "TEST-CASE-X", fake_user)
            assert False, "Non-cyber expert must be rejected"
        except HTTPException as e:
            assert e.status_code == 403
            assert "Cyber Expert access required" in e.detail

        # Cyber expert accessing unassigned case -> 403
        expert = db.query(User).filter(User.role_id == 3).first()
        if not expert:
            expert = User(id=6602, role_id=3, full_name="Expert M", username="expert_m")
            db.add(expert)
            db.commit()

        unassigned_case = db.query(Case).filter(Case.cyber_expert_id != expert.id).first()
        if unassigned_case:
            try:
                authorize_cyber_expert_case_access(db, unassigned_case.id, expert)
                assert False, "Unassigned case must be rejected"
            except HTTPException as e:
                assert e.status_code == 403
                assert "Access denied" in e.detail

        # Nonexistent case -> 404
        try:
            authorize_cyber_expert_case_access(db, "NON_EXISTENT_CASE_9999", expert)
            assert False, "Nonexistent case must return 404"
        except HTTPException as e:
            assert e.status_code == 404
    finally:
        db.close()
    print("PASS: test_4_cyber_expert_authorization_and_case_scoping")


def test_5_metadata_extraction_and_tidb_persistence():
    """Verify case evidence synchronization, Pillow image analysis, and TiDB storage."""
    db = SessionLocal()
    try:
        expert = db.query(User).filter(User.role_id == 3).first()
        if not expert:
            expert = User(id=6603, role_id=3, full_name="Expert M2", username="expert_m2")
            db.add(expert)
            db.commit()

        case = db.query(Case).filter(Case.case_id == "TEST-META-CASE-1").first()
        if not case:
            case = Case(
                case_id="TEST-META-CASE-1",
                title="Forensic Metadata Case",
                description="Case for metadata extraction testing",
                cyber_expert_id=expert.id,
                status="Open",
                priority="Medium"
            )
            db.add(case)
            db.commit()

        # Create real test files in upload dir
        case_dir = backend_dir / "uploads" / "evidence" / str(case.id)
        case_dir.mkdir(parents=True, exist_ok=True)

        # 1. Real image file
        img_path = case_dir / "photo_evidence.png"
        img = Image.new("RGB", (1024, 768), color=(45, 85, 125))
        img.save(img_path)

        # 2. Real document file
        doc_path = case_dir / "statement.txt"
        doc_path.write_text("Official witness statement text content.", encoding="utf-8")

        # Create Evidence and EvidenceHash rows
        ev1 = db.query(Evidence).filter(Evidence.evidence_id == "EV-META-001").first()
        if not ev1:
            ev1 = Evidence(
                evidence_id="EV-META-001",
                case_id=case.id,
                file_name="photo_evidence.png",
                file_type="Image",
                file_size=img_path.stat().st_size,
                file_path=str(img_path).replace("\\", "/"),
                status="Active"
            )
            db.add(ev1)

        ev2 = db.query(Evidence).filter(Evidence.evidence_id == "EV-META-002").first()
        if not ev2:
            ev2 = Evidence(
                evidence_id="EV-META-002",
                case_id=case.id,
                file_name="statement.txt",
                file_type="Document",
                file_size=doc_path.stat().st_size,
                file_path=str(doc_path).replace("\\", "/"),
                status="Active"
            )
            db.add(ev2)
        db.commit()

        # Add hash verification records
        h1 = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev1.id).first()
        if not h1:
            h1 = EvidenceHash(
                evidence_id=ev1.id,
                file_name=ev1.file_name,
                sha256_hash="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                current_hash="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                original_hash="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                hash_match=True,
                tampered=False,
                integrity_status="Verified"
            )
            db.add(h1)

        h2 = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev2.id).first()
        if not h2:
            h2 = EvidenceHash(
                evidence_id=ev2.id,
                file_name=ev2.file_name,
                sha256_hash="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                current_hash="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
                original_hash="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                hash_match=False,
                tampered=True,
                integrity_status="Tampered"
            )
            db.add(h2)
        db.commit()

        # Synchronize metadata using LiveBackendAdapter
        set_backend_adapter(LiveBackendAdapter())
        MetadataService.sync_case_from_adapter(db, str(case.case_id))

        # Verify evidence_records on TiDB
        records = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).all()
        assert len(records) >= 2

        rec_img = next((r for r in records if r.external_evidence_id == "EV-META-001"), None)
        assert rec_img is not None
        assert rec_img.original_filename == "photo_evidence.png"
        assert rec_img.mime_type == "image/png"
        assert rec_img.original_sha256 == h1.original_hash
        assert rec_img.verification_status == "Verified"

        rec_doc = next((r for r in records if r.external_evidence_id == "EV-META-002"), None)
        assert rec_doc is not None
        assert rec_doc.original_filename == "statement.txt"
        assert rec_doc.verification_status == "Tampered"

        # Verify file details card extraction via Pillow
        details_img = MetadataService.get_file_details(db, "EV-META-001", case_id=str(case.case_id))
        assert details_img["file_properties"]["is_image"] is True
        assert details_img["file_properties"]["width"] == 1024
        assert details_img["file_properties"]["height"] == 768
        assert details_img["file_properties"]["dimensions"] == "1024 x 768"
        assert details_img["hash_information"]["sha256"] == h1.original_hash
        assert details_img["hash_information"]["verification_status"] == "Verified"

        details_doc = MetadataService.get_file_details(db, "EV-META-002", case_id=str(case.case_id))
        assert details_doc["file_properties"]["is_image"] is False
        assert details_doc["file_properties"]["image_support_note"] == "Not applicable for non-image file"
        assert details_doc["hash_information"]["verification_status"] == "Tampered"

    finally:
        db.close()
    print("PASS: test_5_metadata_extraction_and_tidb_persistence")


def test_6_idempotent_reprocessing_preserves_records_and_updates():
    """Verify repeated extraction updates in-place, preserves primary keys, and never creates duplicates."""
    db = SessionLocal()
    try:
        case = db.query(Case).filter(Case.case_id == "TEST-META-CASE-1").first()

        # Capture IDs before second sync
        before_records = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).all()
        before_map = {r.external_evidence_id: r.id for r in before_records}
        assert len(before_map) >= 2

        # Re-run synchronization
        MetadataService.sync_case_from_adapter(db, str(case.case_id))

        # Check IDs after re-run
        after_records = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == str(case.case_id)).all()
        after_map = {r.external_evidence_id: r.id for r in after_records}

        assert len(before_records) == len(after_records), "Must not create duplicate evidence_record rows"
        for ext_id, old_pk in before_map.items():
            assert after_map[ext_id] == old_pk, f"Record primary key {old_pk} must be preserved across re-runs"

        # Verify underlying Case, Evidence, EvidenceHash are NOT deleted
        assert db.query(Evidence).filter(Evidence.case_id == case.id).count() >= 2
        assert db.query(EvidenceHash).count() >= 2

    finally:
        db.close()
    print("PASS: test_6_idempotent_reprocessing_preserves_records_and_updates")


def test_7_paginated_searchable_metadata_table():
    """Verify paginated metadata table, search filtering, and sorting."""
    db = SessionLocal()
    try:
        case = db.query(Case).filter(Case.case_id == "TEST-META-CASE-1").first()

        # 1. Full table
        tbl = MetadataService.get_metadata_table(db, str(case.case_id), page=1, page_size=10)
        assert tbl["total_items"] >= 2
        assert len(tbl["items"]) >= 2
        assert tbl["page"] == 1

        # Check item contract matching Screenshot 1
        item0 = tbl["items"][0]
        assert "row_number" in item0
        assert "evidence_id" in item0
        assert "original_filename" in item0
        assert "file_type_display" in item0
        assert "size_formatted" in item0
        assert "created_at_display" in item0
        assert "hash_status" in item0
        assert "details_url" in item0

        # 2. Search filter
        search_res = MetadataService.get_metadata_table(db, str(case.case_id), search="statement")
        assert search_res["total_items"] == 1
        assert search_res["items"][0]["original_filename"] == "statement.txt"

        # 3. Sort by size
        sorted_res = MetadataService.get_metadata_table(db, str(case.case_id), sort_by="size", sort_order="desc")
        assert sorted_res["items"][0]["size_bytes"] >= sorted_res["items"][1]["size_bytes"]

    finally:
        db.close()
    print("PASS: test_7_paginated_searchable_metadata_table")


def test_8_dynamic_case_summary_metrics():
    """Verify summary cards matching Screenshot 1 header."""
    db = SessionLocal()
    try:
        # 1. Populated case
        case = db.query(Case).filter(Case.case_id == "TEST-META-CASE-1").first()
        summary = MetadataService.get_case_summary(db, str(case.case_id))

        assert summary["case_id"] == str(case.case_id)
        assert summary["total_files"] >= 2
        assert summary["total_size_bytes"] > 0
        assert summary["distinct_file_types"] >= 2
        assert summary["latest_upload"] is not None
        assert summary["verified_files_count"] >= 1
        assert summary["tampered_files_count"] >= 1

        # 2. Empty case
        empty_summary = MetadataService.get_case_summary(db, "CASE-NONEXISTENT-EMPTY")
        assert empty_summary["total_files"] == 0
        assert empty_summary["total_size_bytes"] == 0
        assert empty_summary["latest_upload"] is None

    finally:
        db.close()
    print("PASS: test_8_dynamic_case_summary_metrics")


def test_9_cross_case_isolation():
    """Verify cross-case access is blocked and returns 404."""
    db = SessionLocal()
    try:
        expert = db.query(User).filter(User.role_id == 3).first()

        case_1 = db.query(Case).filter(Case.case_id == "TEST-META-CASE-1").first()
        case_2 = db.query(Case).filter(Case.case_id == "TEST-META-CASE-2").first()
        if not case_2:
            case_2 = Case(
                case_id="TEST-META-CASE-2",
                title="Secondary Case",
                cyber_expert_id=expert.id,
                status="Open",
                priority="Low"
            )
            db.add(case_2)
            db.commit()

        # Querying an evidence item belonging to Case 1 using Case 2 context must raise 404
        try:
            MetadataService.get_file_details(db, "EV-META-001", case_id=str(case_2.case_id))
            assert False, "Cross-case evidence access must raise FileNotFoundError"
        except FileNotFoundError:
            pass

        # Case 2 summary must show 0 files
        summary_2 = MetadataService.get_case_summary(db, str(case_2.case_id))
        assert summary_2["total_files"] == 0

    finally:
        db.close()
    print("PASS: test_9_cross_case_isolation")


def test_10_no_frontend_files_touched():
    """Verify git status shows ZERO modifications or additions inside frontend/."""
    out = subprocess.check_output(["git", "status", "--porcelain", "frontend/"]).decode("utf-8")
    assert out.strip() == "", f"Frontend directory must be untouched! Found changes:\n{out}"
    print("PASS: test_10_no_frontend_files_touched")


if __name__ == "__main__":
    print("\n========================================================")
    print("RUNNING METADATA EXTRACTION INTEGRATION TESTS")
    print("========================================================")
    test_1_deepak_core_services_and_classification()
    test_2_deepak_standalone_extract_metadata()
    test_3_routes_registered_and_endpoints_correct()
    test_4_cyber_expert_authorization_and_case_scoping()
    test_5_metadata_extraction_and_tidb_persistence()
    test_6_idempotent_reprocessing_preserves_records_and_updates()
    test_7_paginated_searchable_metadata_table()
    test_8_dynamic_case_summary_metrics()
    test_9_cross_case_isolation()
    test_10_no_frontend_files_touched()
    print("\n========================================================")
    print("ALL 10 METADATA INTEGRATION TESTS PASSED SUCCESSFULLY!")
    print("========================================================")
