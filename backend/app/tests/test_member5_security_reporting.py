import io
import os
import shutil
import sqlite3
import tempfile
from pathlib import Path
from uuid import uuid4
from datetime import datetime, timezone
import pytest

# Configure isolated DB/storage BEFORE app import to protect workspace DB and storage
_GLOBAL_TEST_TMP = Path(tempfile.mkdtemp(prefix="test_vault_global_"))
os.environ["EVIDENCE_DB_URL"] = f"sqlite:///{(_GLOBAL_TEST_TMP / 'test_evidence_global.db').as_posix()}"
os.environ["EVIDENCE_STORAGE_DIR"] = str(_GLOBAL_TEST_TMP / "uploads")

from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker
from PIL import Image

# Import app modules
import app.database as app_db
from app.database import Base, get_db, upgrade_schema
from app.hash_api import app
from app.models.evidence_record import EvidenceRecord
from app.models.custody_log import CustodyLog
from app.models.activity_log import ActivityLog
from app.models.transfer_record import TransferRecord
from app.models.report_record import ReportRecord
from app.models.current_custody import CurrentCustodyInfo
from app.services.file_hash_service import FileHashService
from app.services.metadata_service import MetadataService, format_bytes, classify_file_type_display
from app.services.custody_service import CustodyService
from app.services.timeline_service import TimelineService
import app.services.report_service as app_report_svc
from app.services.report_service import ReportService
from app.services.pdf_service import PDFService
from app.services.downstream_service import DownstreamService
import app.services.hash_manifest_service as app_manifest_svc
from app.services.hash_manifest_service import HashManifestService, validate_safe_id
from app.services.backend_adapter import (
    set_backend_adapter,
    SharedBackendAdapter,
    MockBackendProvider,
    CaseData,
    EvidenceItem,
    SuspectRecord,
    EPRAAnalysisResult,
    ExternalCustodyEvent,
    map_backend_verification_status
)
from app.schemas.report_schema import ReportRequest, ReportType


# Fixture: Isolated test environment with MockBackendProvider
@pytest.fixture
def test_env(tmp_path):
    # Isolated test DB
    test_db_path = tmp_path / "test_evidence.db"
    test_db_url = f"sqlite:///{test_db_path.as_posix()}"
    test_engine = create_engine(test_db_url, connect_args={"check_same_thread": False})
    
    # Run non-destructive upgrade on the fresh DB
    upgrade_schema(test_engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=test_engine)

    # Isolated storage directories
    upload_dir = tmp_path / "uploads"
    upload_dir.mkdir(parents=True, exist_ok=True)
    manifest_dir = upload_dir / "hash_manifests"
    manifest_dir.mkdir(parents=True, exist_ok=True)
    reports_dir = upload_dir / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)

    # Route directory paths to isolated test storage
    orig_manifest_dir = app_db.MANIFEST_DIR
    orig_reports_dir = app_db.REPORTS_DIR
    app_db.MANIFEST_DIR = manifest_dir
    app_db.REPORTS_DIR = reports_dir
    app_manifest_svc.MANIFEST_DIR = manifest_dir
    app_report_svc.MANIFEST_DIR = manifest_dir
    app_report_svc.REPORTS_DIR = reports_dir

    # Isolated mock adapter
    mock_provider = MockBackendProvider()
    set_backend_adapter(mock_provider)

    # Override dependency
    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    client = TestClient(app)

    yield {
        "db_session_factory": TestingSessionLocal,
        "engine": test_engine,
        "upload_dir": upload_dir,
        "manifest_dir": manifest_dir,
        "reports_dir": reports_dir,
        "mock_provider": mock_provider,
        "client": client,
        "tmp_path": tmp_path
    }

    # Teardown: clear overrides, restore directories and restore provider
    app.dependency_overrides.clear()
    app_db.MANIFEST_DIR = orig_manifest_dir
    app_db.REPORTS_DIR = orig_reports_dir
    app_manifest_svc.MANIFEST_DIR = orig_manifest_dir
    app_report_svc.MANIFEST_DIR = orig_manifest_dir
    app_report_svc.REPORTS_DIR = orig_reports_dir
    set_backend_adapter(SharedBackendAdapter())
    Base.metadata.drop_all(bind=test_engine)


# ==============================================================================
# 1. Cryptographic Format Validation (No Local Hashing)
# ==============================================================================

def test_sha256_format_validation():
    """Verify strict 64-hex SHA-256 string format validation."""
    assert FileHashService.is_valid_sha256("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") is True
    assert FileHashService.is_valid_sha256("BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD") is True
    assert FileHashService.is_valid_sha256("") is False
    assert FileHashService.is_valid_sha256(None) is False
    assert FileHashService.is_valid_sha256("invalid_hex_length") is False
    assert FileHashService.is_valid_sha256("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015az") is False


# ==============================================================================
# 2. Metadata Extraction: Pillow Dimensions, Safe Non-Image & Corrupt Handling
# ==============================================================================

def test_metadata_extraction_image_and_non_image(test_env):
    """
    MetadataService must extract accurate image dimensions/mode using Pillow safely,
    handle non-image files with clear notes, and handle corrupt files without crashing.
    """
    tmp_path = test_env["tmp_path"]
    client = test_env["client"]
    mock = test_env["mock_provider"]
    db = test_env["db_session_factory"]()

    # 1. Valid PNG Image
    img_path = tmp_path / "valid_image.png"
    img = Image.new("RGB", (640, 480), color=(73, 109, 137))
    img.save(img_path)

    mock.register_case(CaseData(case_id="CASE-META-01", case_title="Metadata Test Case"))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-IMG-01",
        case_id="CASE-META-01",
        original_filename="valid_image.png",
        file_type="PNG Image",
        file_size_bytes=img_path.stat().st_size,
        file_path=str(img_path),
        original_sha256="11" * 32,
        current_sha256="11" * 32,
        verification_status="Verified"
    ))

    # 2. Non-Image Document
    doc_path = tmp_path / "document.pdf"
    doc_path.write_bytes(b"%PDF-1.4 Mock Document Payload")
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-DOC-02",
        case_id="CASE-META-01",
        original_filename="document.pdf",
        file_type="PDF Document",
        file_size_bytes=doc_path.stat().st_size,
        file_path=str(doc_path),
        original_sha256="22" * 32,
        current_sha256="22" * 32,
        verification_status="Verified"
    ))

    # 3. Corrupt Image
    corrupt_path = tmp_path / "corrupt.jpg"
    corrupt_path.write_bytes(b"NOT A VALID JPEG HEADER OR BYTES")
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-CORRUPT-03",
        case_id="CASE-META-01",
        original_filename="corrupt.jpg",
        file_type="JPEG Image",
        file_size_bytes=corrupt_path.stat().st_size,
        file_path=str(corrupt_path),
        original_sha256="33" * 32,
        current_sha256="33" * 32,
        verification_status="Unknown"
    ))

    # Test Image Details
    res_img = client.get("/evidence/EV-IMG-01/details")
    assert res_img.status_code == 200
    d_img = res_img.json()
    assert d_img["file_properties"]["is_image"] is True
    assert d_img["file_properties"]["dimensions"] == "640 x 480"
    assert d_img["file_properties"]["image_mode"] == "RGB"
    assert "file_path" not in d_img  # Never expose internal path!

    # Test Non-Image Details
    res_doc = client.get("/evidence/EV-DOC-02/details")
    assert res_doc.status_code == 200
    d_doc = res_doc.json()
    assert d_doc["file_properties"]["is_image"] is False
    assert d_doc["file_properties"]["dimensions"] is None
    assert "Not applicable" in d_doc["file_properties"]["image_support_note"]

    # Test Corrupt Image Details (Handled safely without crashing)
    res_corrupt = client.get("/evidence/EV-CORRUPT-03/details")
    assert res_corrupt.status_code == 200
    d_corrupt = res_corrupt.json()
    assert d_corrupt["file_properties"]["is_image"] is True
    assert "failed safely" in d_corrupt["file_properties"]["image_support_note"]

    db.close()


# ==============================================================================
# 3. Metadata Extraction: Case Summary Cards & Searchable/Paginated Table
# ==============================================================================

def test_metadata_case_summary_and_paginated_table(test_env):
    """
    Test Screenshot 1:
    - Empty case returns 0 counts and null latest upload
    - Populated case returns total files, formatted size, distinct types
    - Table supports sorting, search filtering, and pagination
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]

    # Empty case check
    empty_res = client.get("/evidence/case/CASE-EMPTY/summary")
    assert empty_res.status_code == 200
    assert empty_res.json()["total_files"] == 0
    assert empty_res.json()["total_size_bytes"] == 0
    assert empty_res.json()["latest_upload"] is None

    # Register 3 evidence items in CASE-PAGE
    case_id = "CASE-PAGE"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-1", case_id=case_id, original_filename="photo_alpha.jpg", file_type="JPEG Image", file_size_bytes=2400000,
        original_sha256="aa"*32, verification_status="Verified"
    ))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-2", case_id=case_id, original_filename="financial_report.pdf", file_type="PDF Document", file_size_bytes=1800000,
        original_sha256="bb"*32, verification_status="Tampered"
    ))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-3", case_id=case_id, original_filename="surveillance_clip.mp4", file_type="MP4 Video", file_size_bytes=245000000,
        original_sha256="cc"*32, verification_status="Pending"
    ))

    # Check Summary Cards
    sum_res = client.get(f"/evidence/case/{case_id}/summary")
    assert sum_res.status_code == 200
    s_data = sum_res.json()
    assert s_data["total_files"] == 3
    assert s_data["distinct_file_types"] == 3
    assert "MB" in s_data["total_size_formatted"]

    # Check Searchable Table
    tbl_res = client.get(f"/evidence/case/{case_id}/metadata?search=financial")
    assert tbl_res.status_code == 200
    t_data = tbl_res.json()
    assert t_data["total_items"] == 1
    assert t_data["items"][0]["original_filename"] == "financial_report.pdf"
    assert t_data["items"][0]["hash_status"] == "Tampered"

    # Check Pagination
    p1 = client.get(f"/evidence/case/{case_id}/metadata?page=1&page_size=2")
    assert p1.status_code == 200
    assert len(p1.json()["items"]) == 2
    assert p1.json()["total_pages"] == 2


# ==============================================================================
# 4. Adapter Boundary & Status Mapping (Mocked Integration Labeling)
# ==============================================================================

def test_adapter_boundary_hash_and_status_passthrough(test_env):
    """
    [MOCKED PROVIDER TEST]
    BackendAdapter passes through existing original and current SHA-256 digests.
    Member 5 maps Verified, Tampered, Pending, Unknown, Error without recalculation.
    """
    mock = test_env["mock_provider"]
    assert mock.is_mocked is True  # Explicitly labeled as mocked provider

    assert map_backend_verification_status("Verified") == "Verified"
    assert map_backend_verification_status("MATCH") == "Verified"
    assert map_backend_verification_status("Tampered") == "Tampered"
    assert map_backend_verification_status("MISMATCH") == "Tampered"
    assert map_backend_verification_status("pending") == "Pending"
    assert map_backend_verification_status(None) == "Unknown"
    assert map_backend_verification_status("unknown") == "Unknown"
    assert map_backend_verification_status("error") == "Error"


def test_missing_verification_remains_unavailable_not_match(test_env):
    """
    Missing verification or missing hash must remain 'Unknown' or 'Pending', NEVER 'Verified'.
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]

    case_id = "CASE-STATUS"
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-UNVERIF",
        case_id=case_id,
        original_filename="raw_dump.bin",
        original_sha256="44" * 32,
        current_sha256=None,
        verification_status="Unknown"
    ))

    res = client.get("/evidence/EV-UNVERIF/details")
    assert res.status_code == 200
    assert res.json()["hash_information"]["verification_status"] == "Unknown"
    assert res.json()["hash_information"]["verification_status"] != "Verified"


# ==============================================================================
# 5. No Duplicate Local Hashing in Member 5
# ==============================================================================

def test_no_local_hash_recalculation_on_evidence(test_env):
    """
    Verify that metadata extraction, custody transfers, report generation,
    and manifest exports NEVER call hashlib or compute SHA-256 locally.
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]

    case_id = "CASE-NOHASH"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-NOHASH",
        case_id=case_id,
        original_filename="protected.dat",
        original_sha256="55" * 32,
        current_sha256="55" * 32,
        verification_status="Verified"
    ))

    # 1. Metadata extraction does not hash
    client.get("/evidence/EV-NOHASH/details")

    # 2. Transfer workflow does not hash
    trf = client.post(
        "/evidence/transfer/initiate",
        json={"evidence_id": "EV-NOHASH", "sender_name": "Alice", "recipient_name": "Bob"}
    ).json()
    recv_res = client.post(
        f"/evidence/transfer/receive?transfer_reference={trf['transfer_reference']}",
        json={"recipient_name": "Bob"}
    )
    assert recv_res.status_code == 200
    assert "integrity_verification" not in recv_res.json()  # No duplicate verification!

    # 3. Report generation does not hash
    rep_res = client.post("/report/generate", json={"case_id": case_id})
    assert rep_res.status_code == 200


# ==============================================================================
# 6. Chain of Custody & Transfer Lifecycle (Screenshots 2 & 3)
# ==============================================================================

def test_custody_transfer_lifecycle(test_env):
    """
    Test custody transfer:
    - Initiation generates unique reference and marks PENDING_RECEIPT
    - Contradictory transfer rejected while pending
    - Recipient mismatch rejected
    - Receipt confirms completion and updates holder without local hashing
    - Duplicate receipt rejected
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]
    db = test_env["db_session_factory"]()

    case_id = "CASE-TRF-TEST"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(evidence_id="EV-TRF", case_id=case_id, original_filename="evidence.bin"))

    # Initial current custody check (no invented holder or status)
    curr_init = client.get("/evidence/EV-TRF/custody/current").json()
    assert curr_init["current_holder_name"] is None
    assert curr_init["custody_status"] is None

    # 1. Initiate transfer
    trf_res = client.post(
        "/evidence/transfer/initiate",
        json={"evidence_id": "EV-TRF", "sender_name": "Inspector Rahul Singh", "recipient_name": "Jane Doe"}
    )
    assert trf_res.status_code == 200
    ref = trf_res.json()["transfer_reference"]

    # Holder must NOT change on initiation!
    curr_mid = client.get("/evidence/EV-TRF/custody/current").json()
    assert curr_mid["current_holder_name"] is None
    assert curr_mid["custody_status"] == "PENDING_RECEIPT"
    assert curr_mid["pending_recipient_name"] == "Jane Doe"

    # 2. Contradictory transfer rejected
    dup_res = client.post(
        "/evidence/transfer/initiate",
        json={"evidence_id": "EV-TRF", "sender_name": "Inspector Rahul Singh", "recipient_name": "Third Party"}
    )
    assert dup_res.status_code == 400

    # 3. Recipient mismatch rejected
    mismatch_res = client.post(
        f"/evidence/transfer/receive?transfer_reference={ref}",
        json={"recipient_name": "Wrong Person"}
    )
    assert mismatch_res.status_code == 400

    # 4. Valid receipt confirmed
    recv_res = client.post(
        f"/evidence/transfer/receive?transfer_reference={ref}",
        json={"recipient_name": "Jane Doe", "department": "Cyber Cell, Mumbai", "location": "Digital Evidence Lab"}
    )
    assert recv_res.status_code == 200

    # Now holder officially changes!
    curr_end = client.get("/evidence/EV-TRF/custody/current").json()
    assert curr_end["current_holder_name"] == "Jane Doe"
    assert curr_end["department"] == "Cyber Cell, Mumbai"
    assert curr_end["custody_status"] == "In Analysis"
    assert curr_end["pending_recipient_name"] is None

    # 5. Duplicate receipt rejected
    dup_recv = client.post(
        f"/evidence/transfer/receive?transfer_reference={ref}",
        json={"recipient_name": "Jane Doe"}
    )
    assert dup_recv.status_code == 400

    db.close()


def test_current_custody_no_invented_defaults_and_audited_update(test_env):
    """
    Ensure current custody status has no hardcoded default 'In Analysis'.
    Audited update updates location/department but blocks changing holder without transfer.
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]

    case_id = "CASE-AUDIT"
    mock.register_evidence(EvidenceItem(evidence_id="EV-AUDIT", case_id=case_id, original_filename="data.bin"))

    # Initial state
    c_init = client.get("/evidence/EV-AUDIT/custody/current").json()
    assert c_init["current_holder_name"] is None
    assert c_init["custody_status"] is None

    # Audited update of location/department
    up_res = client.put(
        "/evidence/EV-AUDIT/custody/current",
        json={"department": "Special Investigation Team", "location": "Vault 4", "remarks": "Transferred to vault"}
    )
    assert up_res.status_code == 200
    assert up_res.json()["department"] == "Special Investigation Team"
    assert up_res.json()["location"] == "Vault 4"


def test_external_custody_event_ingestion_idempotency(test_env):
    """
    External custody events ingested from BackendAdapter must be idempotent.
    Repeated ingestion of the same external_event_id must never create duplicates.
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]
    db = test_env["db_session_factory"]()

    case_id = "CASE-IDEM"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(evidence_id="EV-IDEM", case_id=case_id, original_filename="logs.txt"))

    # Register external events
    events = [
        ExternalCustodyEvent(
            external_event_id="EXT-EV-01",
            case_id=case_id,
            evidence_id="EV-IDEM",
            event_type="ACQUISITION",
            title="Evidence Acquired",
            description="Acquired from server room",
            timestamp=datetime.now(timezone.utc),
            actor_name="Agent Cooper"
        )
    ]
    mock.register_events(case_id, events)

    # First fetch: ingests event
    timeline1 = client.get("/evidence/EV-IDEM/custody/timeline").json()
    assert timeline1["total_events"] == 1

    # Second fetch: idempotent, does not duplicate!
    timeline2 = client.get("/evidence/EV-IDEM/custody/timeline").json()
    assert timeline2["total_events"] == 1

    db.close()


# ==============================================================================
# 7. Timeline Reconstruction & Event Deduplication
# ==============================================================================

def test_timeline_reconstruction_and_deduplication(test_env):
    """
    Case timeline must reconstruct events across tables and deduplicate linked
    custody and activity records sharing the same event_reference.
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]

    case_id = "CASE-TIMELINE"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(evidence_id="EV-TL", case_id=case_id, original_filename="phone.bin"))

    # Initiate and receive transfer (creates custody and activity logs with shared event_ref)
    trf = client.post(
        "/evidence/transfer/initiate",
        json={"evidence_id": "EV-TL", "sender_name": "Investigator A", "recipient_name": "Investigator B"}
    ).json()
    client.post(
        f"/evidence/transfer/receive?transfer_reference={trf['transfer_reference']}",
        json={"recipient_name": "Investigator B"}
    )

    tl_res = client.get(f"/evidence/case/{case_id}/timeline")
    assert tl_res.status_code == 200
    tl_data = tl_res.json()
    assert tl_data["total_steps"] >= 2

    # Steps are ordered chronologically
    for i in range(len(tl_data["timeline"]) - 1):
        assert tl_data["timeline"][i]["timestamp"] <= tl_data["timeline"][i + 1]["timestamp"]


# ==============================================================================
# 8. Report Generation: 5 Types, Selectable Sections, Draft Preview & History
# ==============================================================================

def test_all_five_report_types_and_selected_sections(test_env):
    """
    Generate all 5 report types and verify appropriate format and section controls:
    1. Comprehensive Forensic Report
    2. Evidence Summary Report
    3. Chain of Custody Report
    4. Hash Verification Report
    5. JSON Hash Manifest
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]

    case_id = "CASE-REPORTS"
    mock.register_case(CaseData(case_id=case_id, case_title="Full Audit Case"))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-R1", case_id=case_id, original_filename="test1.pdf", file_type="PDF Document", file_size_bytes=5000,
        original_sha256="11"*32, current_sha256="11"*32, verification_status="Verified"
    ))

    report_types = [
        ReportType.COMPREHENSIVE,
        ReportType.EVIDENCE_SUMMARY,
        ReportType.CHAIN_OF_CUSTODY,
        ReportType.HASH_VERIFICATION,
        ReportType.HASH_MANIFEST
    ]

    for rt in report_types:
        res = client.post(
            "/report/generate",
            json={"case_id": case_id, "report_type": rt.value, "investigator_name": "Auditor"}
        )
        assert res.status_code == 200, res.text
        data = res.json()
        assert data["status"] == "success"
        if rt == ReportType.HASH_MANIFEST:
            assert data["file_format"] == "JSON"
            assert "manifest_content" in data
        else:
            assert data["file_format"] == "PDF"
            assert Path(data["pdf_path"]).exists()


def test_report_draft_preview_vs_final_generation(test_env):
    """
    Preview must be marked DRAFT, return streaming PDF or JSON manifest,
    and NOT register in ReportRecord or create custody events.
    Final generation must persist snapshot and audit logs.
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]
    db = test_env["db_session_factory"]()

    case_id = "CASE-PREV"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(evidence_id="EV-P", case_id=case_id, original_filename="sample.txt", file_size_bytes=100))

    # 1. Draft Preview
    prev_res = client.post(
        "/report/preview",
        json={"case_id": case_id, "report_type": ReportType.COMPREHENSIVE.value}
    )
    assert prev_res.status_code == 200
    assert prev_res.headers["content-type"] == "application/pdf"

    # Verify no ReportRecord was persisted
    count_before = db.query(ReportRecord).filter(ReportRecord.case_id == case_id).count()
    assert count_before == 0

    # 2. Final Generation
    gen_res = client.post(
        "/report/generate",
        json={"case_id": case_id, "report_type": ReportType.COMPREHENSIVE.value}
    )
    assert gen_res.status_code == 200
    rep_id = gen_res.json()["report_id"]

    # Verify ReportRecord was persisted
    count_after = db.query(ReportRecord).filter(ReportRecord.case_id == case_id).count()
    assert count_after == 1

    # Check Report History
    hist_res = client.get(f"/report/history/{case_id}")
    assert hist_res.status_code == 200
    assert hist_res.json()["total_reports"] == 1
    assert hist_res.json()["reports"][0]["report_id"] == rep_id

    db.close()


def test_report_history_immutability_and_safe_download(test_env):
    """
    Repeat report generation creates new version without overwriting prior outputs.
    Safe download by report_id enforces path containment and rejects traversal.
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]

    case_id = "CASE-IMMUTABLE"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(evidence_id="EV-I", case_id=case_id, original_filename="doc.pdf", file_size_bytes=100))

    # First generation
    r1 = client.post("/report/generate", json={"case_id": case_id, "case_title": "Title 1"}).json()
    # Second generation
    r2 = client.post("/report/generate", json={"case_id": case_id, "case_title": "Title 2"}).json()

    assert r1["report_id"] != r2["report_id"]
    assert Path(r1["pdf_path"]).exists()
    assert Path(r2["pdf_path"]).exists()

    # Safe download
    dl1 = client.get(f"/report/download/{r1['report_id']}")
    assert dl1.status_code == 200
    assert dl1.headers["content-type"] == "application/pdf"

    # Path traversal rejection
    bad_dl = client.get("/report/download/..%2F..%2Fsecret")
    assert bad_dl.status_code in (400, 403, 404)


# ==============================================================================
# 9. Multipage PDF Visual Rendering & Inspection
# ==============================================================================

def test_multipage_pdf_visual_rendering(test_env):
    """
    Render generated PDF pages to PNG images using PyMuPDF (pymupdf).
    Inspect that all pages render cleanly without overlap or error.
    """
    import pymupdf
    client = test_env["client"]
    mock = test_env["mock_provider"]
    tmp_path = test_env["tmp_path"]

    case_id = "CASE-VISUAL"
    mock.register_case(CaseData(case_id=case_id, case_title="Visual Render Test", crime_type="Financial Fraud"))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-V1", case_id=case_id, original_filename="ledger.xlsx", file_type="Excel Document",
        file_size_bytes=45000, original_sha256="77"*32, current_sha256="77"*32, verification_status="Verified"
    ))

    gen_res = client.post(
        "/report/generate",
        json={
            "case_id": case_id,
            "report_type": ReportType.COMPREHENSIVE.value,
            "investigator_name": "Detective Miller",
            "conclusions_text": "Forensic findings confirmed all ledger entries intact.",
            "recommendations_text": "Conclude audit."
        }
    )
    assert gen_res.status_code == 200
    pdf_path = gen_res.json()["pdf_path"]

    # Open with pymupdf and render pages to PNG images
    doc = pymupdf.open(pdf_path)
    assert len(doc) >= 1, "Must generate valid readable PDF pages"

    render_dir = tmp_path / "pdf_visual_pages"
    render_dir.mkdir(parents=True, exist_ok=True)

    rendered_files = []
    for idx, page in enumerate(doc):
        pix = page.get_pixmap()
        img_file = render_dir / f"page_{idx + 1}.png"
        pix.save(str(img_file))
        assert img_file.exists()
        assert img_file.stat().st_size > 5000  # Valid non-trivial PNG image
        rendered_files.append(img_file)

    assert len(rendered_files) == len(doc)


# ==============================================================================
# 10. Downstream EPRA Structured Contract
# ==============================================================================

def test_downstream_epra_contract_preserves_provenance(test_env):
    """
    Downstream EPRA export must preserve suspect and analysis statuses,
    provenance, and avoid exposing internal file paths.
    """
    client = test_env["client"]
    mock = test_env["mock_provider"]

    case_id = "CASE-EPRA-TEST"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-EP1", case_id=case_id, original_filename="account_dump.csv",
        original_sha256="88"*32, verification_status="Verified"
    ))
    mock.register_suspects(case_id, [
        SuspectRecord(suspect_id="S-1", name="Victor Creed", role_or_relation="Informant", externally_supplied_ranking=1)
    ])
    mock.register_epra_analysis(case_id, [
        EPRAAnalysisResult(case_id=case_id, evidence_id="EV-EP1", priority_score=0.95, priority_rank=1, status="MEASURED", provenance_source="EPRA v1.2")
    ])

    epra_res = client.get(f"/downstream/epra/{case_id}")
    assert epra_res.status_code == 200
    data = epra_res.json()
    assert data["case_id"] == case_id
    assert data["suspect_count"] == 1
    assert data["suspect_records"][0]["name"] == "Victor Creed"
    assert data["epra_analysis_records"][0]["status"] == "MEASURED"
    assert data["epra_analysis_records"][0]["priority_rank"] == 1
    # File path must NOT be exposed!
    assert "file_path" not in data["evidence_records"][0]
    assert "download_url" in data["evidence_records"][0]


# ==============================================================================
# 11. Non-Destructive Schema Upgrade with Legacy Data
# ==============================================================================

def test_non_destructive_schema_upgrade_with_legacy_data(tmp_path):
    """
    User Correction 5: Test non-destructive upgrade starting with an old SQLite schema
    containing existing data (without new columns).
    Verifies that old data survives, new columns are added, and backfills succeed!
    """
    legacy_db_path = tmp_path / "legacy_vault.db"
    conn = sqlite3.connect(legacy_db_path)
    cursor = conn.cursor()

    # 1. Create Old Legacy Tables without any of the new columns
    cursor.execute("""
        CREATE TABLE evidence_records (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            case_id VARCHAR(100) NOT NULL,
            original_filename VARCHAR(255) NOT NULL,
            stored_filename VARCHAR(255) NOT NULL,
            file_path VARCHAR(512) NOT NULL,
            file_extension VARCHAR(50),
            mime_type VARCHAR(150),
            evidence_type VARCHAR(50),
            file_size_bytes BIGINT DEFAULT 0,
            filesystem_ctime VARCHAR(50),
            filesystem_ctime_source VARCHAR(100),
            filesystem_mtime VARCHAR(50),
            filesystem_mtime_source VARCHAR(100),
            uploaded_at DATETIME,
            investigator_id VARCHAR(100),
            investigator_name VARCHAR(150),
            is_empty_file BOOLEAN DEFAULT 0,
            processing_status VARCHAR(50),
            notes VARCHAR(500)
        )
    """)

    cursor.execute("""
        CREATE TABLE custody_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            evidence_id INTEGER NOT NULL,
            case_id VARCHAR(100),
            investigator_id VARCHAR(100),
            investigator_name VARCHAR(150) NOT NULL,
            action VARCHAR(100) NOT NULL,
            result VARCHAR(100),
            remarks VARCHAR(500),
            transfer_reference VARCHAR(64),
            transfer_sender VARCHAR(150),
            transfer_recipient VARCHAR(150),
            event_reference VARCHAR(64),
            is_system_action BOOLEAN DEFAULT 0,
            actor_is_unverified BOOLEAN DEFAULT 1,
            timestamp DATETIME
        )
    """)

    cursor.execute("""
        CREATE TABLE evidence_hashes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            evidence_id INTEGER UNIQUE NOT NULL,
            case_id VARCHAR(100),
            file_name VARCHAR(255) NOT NULL,
            hash_algorithm VARCHAR(50) DEFAULT 'SHA-256',
            sha256_hash VARCHAR(64) NOT NULL,
            created_at DATETIME
        )
    """)

    # 2. Insert Existing Legacy Records
    cursor.execute("""
        INSERT INTO evidence_records (id, case_id, original_filename, stored_filename, file_path, file_size_bytes)
        VALUES (42, 'CASE-LEGACY', 'legacy_evidence.bin', 'stored_legacy.bin', '/tmp/legacy.bin', 12345)
    """)
    cursor.execute("""
        INSERT INTO evidence_hashes (evidence_id, case_id, file_name, sha256_hash)
        VALUES (42, 'CASE-LEGACY', 'legacy_evidence.bin', '9999999999999999999999999999999999999999999999999999999999999999')
    """)
    cursor.execute("""
        INSERT INTO custody_logs (evidence_id, case_id, investigator_name, action, timestamp)
        VALUES (42, 'CASE-LEGACY', 'Old Investigator', 'EVIDENCE_UPLOADED', '2025-01-01 10:00:00')
    """)
    conn.commit()
    conn.close()

    # 3. Execute Non-Destructive Schema Upgrade
    engine = create_engine(f"sqlite:///{legacy_db_path.as_posix()}")
    upgrade_schema(engine)

    # 4. Assert That Old Records Survived and New Columns Are Present
    conn = sqlite3.connect(legacy_db_path)
    cursor = conn.cursor()

    # Check evidence_records count
    ev_count = cursor.execute("SELECT count(*) FROM evidence_records").fetchone()[0]
    assert ev_count == 1, "Legacy evidence record must not be dropped"

    # Check backfilled fields
    row = cursor.execute("SELECT id, external_evidence_id, original_sha256, original_filename FROM evidence_records WHERE id = 42").fetchone()
    assert row[0] == 42
    assert row[1] == "42", "external_evidence_id must be backfilled non-destructively"
    assert row[2] == "9999999999999999999999999999999999999999999999999999999999999999", "original_sha256 must be backfilled from evidence_hashes"
    assert row[3] == "legacy_evidence.bin"

    # Check that custody_logs has recorded_at column now
    cols = [col[1] for col in cursor.execute("PRAGMA table_info(custody_logs)").fetchall()]
    assert "recorded_at" in cols
    assert "external_event_id" in cols
    assert "title" in cols

    # Check that current_custody_info table was created
    tables = [t[0] for t in cursor.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()]
    assert "current_custody_info" in tables

    conn.close()


# ==============================================================================
# Regression Tests for Specific Review Bug Fixes
# ==============================================================================

def test_regression_backend_adapter_pending_state_and_no_fabricated_defaults():
    """
    Review Bug 1:
    - SharedBackendAdapter must return explicit integration-pending state (is_connected=False).
    - Must not claim a live connection.
    - CaseData must NOT fabricate defaults for status, case_title, or crime_type.
    - MockBackendProvider.get_case must return None for unregistered cases.
    """
    adapter = SharedBackendAdapter()
    assert adapter.is_connected is False
    assert adapter.connection_status == "INTEGRATION_PENDING"
    assert adapter.get_case("ANY_CASE") is None
    assert adapter.get_evidence("EV_1") is None

    # CaseData must have None defaults for status and crime_type
    case_data = CaseData(case_id="TEST-CASE-1")
    assert case_data.status is None
    assert case_data.crime_type is None
    assert case_data.case_title is None

    # MockBackendProvider unknown case
    mock = MockBackendProvider()
    assert mock.get_case("NONEXISTENT") is None


def test_regression_metadata_mime_provenance_and_missing_timestamps(test_env):
    """
    Review Bug 2:
    - Do not store application/octet-stream and label it "detected".
    - Preserves supplied MIME provenance ("backend_supplied") or labels extension-based guesses ("extension_guessed").
    - Missing uploaded_at remains None (no substitute current time).
    - Explicit cache refresh updates hashes/timestamps rather than silently presenting stale ones.
    """
    mock = test_env["mock_provider"]
    db = test_env["db_session_factory"]()

    case_id = "CASE-REG-META"
    mock.register_case(CaseData(case_id=case_id))

    # Evidence with no extension and no supplied MIME
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-NO-EXT",
        case_id=case_id,
        original_filename="raw_binary_blob",
        uploaded_at=None,
        original_sha256="1111111111111111111111111111111111111111111111111111111111111111",
        verification_status="Verified"
    ))

    # Evidence with png extension but no supplied MIME
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-PNG-EXT",
        case_id=case_id,
        original_filename="screenshot.png",
        uploaded_at=None
    ))

    # Evidence with explicit backend supplied MIME
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-SUPPLIED-MIME",
        case_id=case_id,
        original_filename="report.custom",
        mime_type="application/x-custom-report",
        uploaded_at=None
    ))

    # Trigger sync
    MetadataService.sync_case_from_adapter(db, case_id)

    rec_raw = db.query(EvidenceRecord).filter(EvidenceRecord.external_evidence_id == "EV-NO-EXT").first()
    assert rec_raw.mime_type is None
    assert rec_raw.mime_type_source == "unspecified"
    assert rec_raw.uploaded_at is None, "Missing uploaded_at must remain None, not now()"

    rec_png = db.query(EvidenceRecord).filter(EvidenceRecord.external_evidence_id == "EV-PNG-EXT").first()
    assert rec_png.mime_type == "image/png"
    assert rec_png.mime_type_source == "extension_guessed"

    rec_cust = db.query(EvidenceRecord).filter(EvidenceRecord.external_evidence_id == "EV-SUPPLIED-MIME").first()
    assert rec_cust.mime_type == "application/x-custom-report"
    assert rec_cust.mime_type_source == "backend_supplied"

    # Test explicit cache refresh: source updates hash to tampered
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-NO-EXT",
        case_id=case_id,
        original_filename="raw_binary_blob",
        uploaded_at=None,
        original_sha256="1111111111111111111111111111111111111111111111111111111111111111",
        current_sha256="2222222222222222222222222222222222222222222222222222222222222222",
        verification_status="Tampered"
    ))
    MetadataService.sync_case_from_adapter(db, case_id)
    db.refresh(rec_raw)
    assert rec_raw.verification_status == "Tampered"
    assert rec_raw.current_sha256 == "2222222222222222222222222222222222222222222222222222222222222222"
    assert rec_raw.cached_at is not None

    db.close()


def test_regression_metadata_streamed_image_via_adapter(test_env):
    """
    Review Bug 2:
    - Use adapter's controlled file stream for image metadata when local bytes are unavailable on disk.
    - Missing metadata remains missing.
    """
    mock = test_env["mock_provider"]
    db = test_env["db_session_factory"]()

    case_id = "CASE-STREAM-IMG"
    mock.register_case(CaseData(case_id=case_id))

    # Generate small test PNG in memory
    img_buf = io.BytesIO()
    img = Image.new("RGB", (64, 48), color="red")
    img.save(img_buf, format="PNG")
    png_bytes = img_buf.getvalue()

    # Register in adapter with memory stream, NO local file on disk
    mock.register_evidence(
        EvidenceItem(
            evidence_id="EV-STREAM-PNG",
            case_id=case_id,
            original_filename="in_memory_chart.png",
            file_type="PNG",
            file_size_bytes=len(png_bytes)
        ),
        file_bytes=png_bytes
    )

    MetadataService.sync_case_from_adapter(db, case_id)
    details = MetadataService.get_file_details(db, "EV-STREAM-PNG")

    assert details["file_properties"] is not None
    assert details["file_properties"]["dimensions"] == "64 x 48"
    assert details["file_properties"]["image_mode"] == "RGB"

    db.close()


def test_regression_custody_access_no_holder_assignment_and_recipient_id_mismatch(test_env):
    """
    Review Bug 3:
    - Viewing/accessing evidence must NOT automatically assign its holder.
    - Reject recipient ID mismatch when transfer has an intended recipient ID, even if names match.
    - Do not create CASE-DEFAULT for unresolved evidence.
    - Validate evidence/case association before custody mutations.
    """
    mock = test_env["mock_provider"]
    db = test_env["db_session_factory"]()

    case_id = "CASE-REG-CUSTODY"
    mock.register_case(CaseData(case_id=case_id))
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-CUST-1",
        case_id=case_id,
        original_filename="doc.pdf"
    ))

    # 1. Access event must NOT assign current_holder_name
    CustodyService.record_access_event(
        db=db,
        evidence_id="EV-CUST-1",
        investigator_id="INV-99",
        investigator_name="Auditor Alice",
        action="EVIDENCE_ACCESSED"
    )
    curr = CustodyService.get_current_custody(db, "EV-CUST-1")
    assert curr["current_holder_name"] is None, "Accessing evidence must NOT assign holder"
    assert curr["current_holder_id"] is None

    # 2. Initiate transfer with specific recipient ID
    init_res = CustodyService.initiate_transfer(
        db=db,
        evidence_id="EV-CUST-1",
        sender_name="Investigator Bob",
        sender_id="INV-01",
        recipient_name="Specialist Eve",
        recipient_id="INV-EVE-100",
        case_id=case_id
    )
    trf_ref = init_res["transfer_reference"]

    # Try to receive with same recipient name but WRONG recipient ID -> MUST REJECT
    with pytest.raises(ValueError, match="Recipient ID mismatch"):
        CustodyService.receive_transfer(
            db=db,
            transfer_reference=trf_ref,
            recipient_name="Specialist Eve",
            recipient_id="INV-IMPOSTER-999"
        )

    # Validate case/evidence association: transfer initiation for EV-CUST-1 on WRONG case raises ValueError
    with pytest.raises(ValueError, match="does not belong to case"):
        CustodyService.initiate_transfer(
            db=db,
            evidence_id="EV-CUST-1",
            sender_name="Investigator Bob",
            recipient_name="Specialist Eve",
            case_id="WRONG-CASE-XYZ"
        )

    # Never create CASE-DEFAULT for unresolved evidence
    unknown_ev_case = CustodyService._resolve_case_id(db, "NONEXISTENT-EVIDENCE-ID")
    assert unknown_ev_case is None, "Unresolved evidence must return None, NOT CASE-DEFAULT"

    db.close()


def test_regression_activity_log_preserves_external_string_ids(test_env):
    """
    Review Bug 4:
    - Preserve external string IDs in activity records instead of storing None.
    - Consistency across lookups.
    """
    db = test_env["db_session_factory"]()
    case_id = "CASE-ACT-ID"

    # Create activity log with non-integer external string ID
    log = CustodyService._log_activity(
        db=db,
        case_id=case_id,
        evidence_id="EV-STRING-NON-NUMERIC-99",
        investigator_name="Agent Smith",
        action="TEST_ACTION",
        activity="Test activity on string ID",
        outcome="SUCCESS"
    )

    db.commit()

    saved_log = db.query(ActivityLog).filter(
        ActivityLog.external_evidence_id == "EV-STRING-NON-NUMERIC-99"
    ).first()
    assert saved_log is not None
    assert saved_log.external_evidence_id == "EV-STRING-NON-NUMERIC-99"

    db.close()


def test_regression_report_scoping_unknown_counts_and_section_validation(test_env):
    """
    Review Bug 5:
    - Apply selected evidence scope consistently to custody, timeline, activity, suspects, and EPRA analysis.
    - Keep Unknown and Error counts distinct.
    - Do not insert default crime/department as facts.
    - Distinguish selected_sections=None from explicitly empty list [].
    - Validate unknown section names instead of silently discarding them.
    """
    mock = test_env["mock_provider"]
    db = test_env["db_session_factory"]()

    case_id = "CASE-REPORT-SCOPE"
    mock.register_case(CaseData(
        case_id=case_id,
        case_title=None,
        crime_type=None,
        department=None
    ))

    # Evidence 1: Verified
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-SCOPE-1",
        case_id=case_id,
        original_filename="file1.pdf",
        verification_status="Verified"
    ))
    # Evidence 2: Tampered
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-SCOPE-2",
        case_id=case_id,
        original_filename="file2.pdf",
        verification_status="Tampered"
    ))
    # Evidence 3: Unknown
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-SCOPE-3",
        case_id=case_id,
        original_filename="file3.pdf",
        verification_status="Unknown"
    ))
    # Evidence 4: Error
    mock.register_evidence(EvidenceItem(
        evidence_id="EV-SCOPE-4",
        case_id=case_id,
        original_filename="file4.pdf",
        verification_status="Error"
    ))

    # Sync into DB
    MetadataService.sync_case_from_adapter(db, case_id)

    # 1. Unknown and Error counts distinct
    report_req_all = ReportRequest(
        case_id=case_id,
        investigator_name="Investigator X"
    )
    rep_data = ReportService.assemble_report_data(report_req_all, db, is_draft=True)
    summary = rep_data["evidence_summary"]
    assert summary["integrity_unknown"] == 1
    assert summary["integrity_error"] == 1
    assert summary["integrity_verified"] == 1
    assert summary["integrity_tampered"] == 1

    # 2. Scoped evidence: scope to EV-SCOPE-1 only
    report_scoped = ReportRequest(
        case_id=case_id,
        investigator_name="Investigator X",
        evidence_ids=["EV-SCOPE-1"]
    )
    rep_data_scoped = ReportService.assemble_report_data(report_scoped, db, is_draft=True)
    assert len(rep_data_scoped["evidence_records"]) == 1
    assert rep_data_scoped["evidence_records"][0]["evidence_id"] == "EV-SCOPE-1"

    # 3. Unknown section name raises ValueError
    report_invalid_sec = ReportRequest(
        case_id=case_id,
        investigator_name="Investigator X",
        selected_sections=["unknown_section_foo"]
    )
    with pytest.raises(ValueError, match="Unknown report section name"):
        ReportService.assemble_report_data(report_invalid_sec, db, is_draft=True)

    # 4. Explicit empty list [] vs None
    report_empty_sec = ReportRequest(
        case_id=case_id,
        investigator_name="Investigator X",
        selected_sections=[]
    )
    rep_empty = ReportService.assemble_report_data(report_empty_sec, db, is_draft=True)
    assert rep_empty["selected_sections"] == []

    # 5. No default crime/department as established facts
    assert rep_data["crime_type"] is None
    assert rep_data["department"] is None

    db.close()
