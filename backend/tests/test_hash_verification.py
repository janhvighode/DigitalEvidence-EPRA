import os
import sys
import tempfile
import hashlib
from pathlib import Path

# Add backend directory to path
backend_dir = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException
from fastapi.security import HTTPAuthorizationCredentials

from app.main import app
from database.database import SessionLocal
from models.role import Role
from models.user import User
from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from services.hash_service import HashService
from services.file_hash_service import FileHashService
from services.integrity_service import IntegrityService
from services.tamper_service import TamperService
from services.storage_service import StorageService
from services.hash_verification_service import HashVerificationService
from services.evidence_service import (
    get_case_or_404,
    authorize_case_access,
    get_case_evidence_list,
    get_evidence_details,
    generate_evidence_id,
)
from utils.jwt_handler import verify_access_token
from utils.current_user import get_current_user


from routes.evidence_routes import router as evidence_router


def test_1_backend_imports_and_routes_registered():
    """Verify application initializes and all new endpoints are mounted."""
    expected_paths = {
        "/cases/{case_id}/hash-verification/summary",
        "/cases/{case_id}/evidence",
        "/cases/{case_id}/evidence/{evidence_id}/hash-verification",
    }
    router_paths = {route.path for route in evidence_router.routes}
    for path in expected_paths:
        assert path in router_paths
    assert any(getattr(r, "original_router", None) is evidence_router for r in app.routes)


def test_2_real_sha256_generation_and_consistency():
    """Verify Member 5 HashService produces real valid SHA-256 and is consistent."""
    with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as tmp:
        tmp.write(b"Digital Evidence Test Payload 12345")
        tmp_path = tmp.name

    try:
        expected_sha = hashlib.sha256(b"Digital Evidence Test Payload 12345").hexdigest()
        generated_sha = HashService.generate_sha256(tmp_path)

        assert len(generated_sha) == 64
        assert generated_sha == expected_sha

        # Same file produces identical SHA-256
        second_sha = HashService.generate_sha256(tmp_path)
        assert second_sha == generated_sha

        # FileHashService produces identical SHA-256
        file_hash_sha = FileHashService.generate_sha256(tmp_path)
        assert file_hash_sha == generated_sha
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_3_sha256_detects_file_modification():
    """Verify modifying file contents produces a completely different SHA-256 hash."""
    with tempfile.NamedTemporaryFile(delete=False, suffix=".bin") as tmp:
        tmp.write(b"Original Evidence Content")
        tmp_path = tmp.name

    try:
        hash_before = HashService.generate_sha256(tmp_path)

        # Modify file
        with open(tmp_path, "wb") as f:
            f.write(b"Tampered Evidence Content")

        hash_after = HashService.generate_sha256(tmp_path)

        assert hash_before != hash_after
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)


def test_4_member5_integrity_service():
    """Verify Member 5 IntegrityService behavior."""
    h1 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    h2 = "ca978112ca1bbdcafac231b39a23dc4da7860814965f747021a6823843614046"

    # Matching
    res_verified = IntegrityService.verify_integrity(h1, h1)
    assert res_verified["status"] == "Verified"
    assert res_verified["tampered"] is False

    # Mismatched
    res_tampered = IntegrityService.verify_integrity(h1, h2)
    assert res_tampered["status"] == "Tampered"
    assert res_tampered["tampered"] is True


def test_5_member5_tamper_service():
    """Verify Member 5 TamperService behavior."""
    h1 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    h2 = "ca978112ca1bbdcafac231b39a23dc4da7860814965f747021a6823843614046"

    res_auth = TamperService.detect_tampering(h1, h1)
    assert res_auth["status"] == "Original"

    res_tamp = TamperService.detect_tampering(h1, h2)
    assert res_tamp["status"] == "Tampered"


def test_6_forensic_rule_no_original_hash_results_in_unknown():
    """FORENSIC RULE: If no reference hash is provided, status MUST be Unknown."""
    current_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    result = HashVerificationService.verify_evidence_integrity(
        original_hash=None,
        current_hash=current_hash
    )

    assert result["original_hash"] is None
    assert result["current_hash"] == current_hash
    assert result["hash_match"] is None
    assert result["tampered"] is None
    assert result["integrity_status"] == "Unknown"

    # Also with empty string
    result_empty = HashVerificationService.verify_evidence_integrity(
        original_hash="   ",
        current_hash=current_hash
    )
    assert result_empty["integrity_status"] == "Unknown"
    assert result_empty["hash_match"] is None


def test_7_forensic_rule_matching_original_hash_results_in_verified():
    """FORENSIC RULE: If reference hash matches current hash, status MUST be Verified."""
    current_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    result = HashVerificationService.verify_evidence_integrity(
        original_hash=current_hash.upper(),  # case-insensitive check
        current_hash=current_hash
    )

    assert result["hash_match"] is True
    assert result["tampered"] is False
    assert result["integrity_status"] == "Verified"


def test_8_forensic_rule_different_hashes_results_in_tampered():
    """FORENSIC RULE: If reference hash differs from current hash, status MUST be Tampered."""
    original_hash = "ca978112ca1bbdcafac231b39a23dc4da7860814965f747021a6823843614046"
    current_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    result = HashVerificationService.verify_evidence_integrity(
        original_hash=original_hash,
        current_hash=current_hash
    )

    assert result["hash_match"] is False
    assert result["tampered"] is True
    assert result["integrity_status"] == "Tampered"


def test_9_storage_service_file_categorization():
    """Verify file categorization handles Images, Documents, Videos, etc."""
    assert StorageService._categorize_file_type("image/png", ".png") == "Image"
    assert StorageService._categorize_file_type("application/pdf", ".pdf") == "PDF Document"
    assert StorageService._categorize_file_type("video/mp4", ".mp4") == "Video"
    assert StorageService._categorize_file_type(None, ".jpg") == "Image"
    assert StorageService._categorize_file_type(None, ".docx") == "Document"


def test_10_missing_or_invalid_jwt_rejected():
    """Security check: Invalid JWT is rejected with 401."""
    # 1. verify_access_token returns None on garbage
    assert verify_access_token("invalid_garbage_token") is None
    assert verify_access_token("") is None

    # 2. get_current_user raises HTTPException(401) on invalid credentials
    db = SessionLocal()
    try:
        credentials = HTTPAuthorizationCredentials(
            scheme="Bearer",
            credentials="invalid_or_tampered_token"
        )
        try:
            get_current_user(credentials=credentials, db=db)
            assert False, "Should have raised HTTPException(401)"
        except HTTPException as exc:
            assert exc.status_code == 401
    finally:
        db.close()


def test_11_authorization_logic_and_case_access():
    """Verify role authorization for Cyber Expert, Investigator, and Admin."""
    db = SessionLocal()
    try:
        case = db.query(Case).first()
        if not case:
            return  # No cases in DB to test

        # Case.cyber_expert_id assigned user
        cyber_expert = User(id=case.cyber_expert_id, role_id=3, full_name="Authorized CE")
        unauthorized_expert = User(id=99999999, role_id=3, full_name="Unauthorized CE")

        # Authorized cyber expert passes
        authorized_case = authorize_case_access(db, case.id, cyber_expert)
        assert authorized_case.id == case.id

        # Unauthorized cyber expert is blocked with 403
        try:
            authorize_case_access(db, case.id, unauthorized_expert)
            assert False, "Expected 403 HTTPException"
        except HTTPException as exc:
            assert exc.status_code == 403
            assert "not assigned as Cyber Expert" in exc.detail

        # Non-existent case raises 404
        try:
            authorize_case_access(db, 99999999, cyber_expert)
            assert False, "Expected 404 HTTPException"
        except HTTPException as exc:
            assert exc.status_code == 404
    finally:
        db.close()


def test_12_evidence_not_found_raises_404():
    """Verify get_evidence_details raises 404 for invalid evidence."""
    db = SessionLocal()
    try:
        case = db.query(Case).first()
        if not case:
            return

        try:
            get_evidence_details(db, case, "NON_EXISTENT_EV_999")
            assert False, "Expected 404 for missing evidence"
        except HTTPException as exc:
            assert exc.status_code == 404
    finally:
        db.close()


def test_13_case_hash_summary_counts():
    """Verify HashVerificationService.get_case_hash_summary produces valid case-wise counts."""
    db = SessionLocal()
    try:
        case = db.query(Case).first()
        if not case:
            return

        summary = HashVerificationService.get_case_hash_summary(db, case)
        assert "case_id" in summary
        assert "total_evidence" in summary
        assert "verified" in summary
        assert "tampered" in summary
        assert "pending" in summary
        assert summary["total_evidence"] == (
            summary["verified"] + summary["tampered"] + summary["pending"]
        )
    finally:
        db.close()


def test_14_existing_database_connectivity_and_tables_untouched():
    """Database integrity: Verify connection to TiDB and existing schema is intact."""
    db = SessionLocal()
    try:
        roles = db.query(Role).all()
        assert len(roles) >= 3

        role_names = [r.role_name for r in roles]
        assert "Administrator" in role_names
        assert "Investigator" in role_names
        assert "Cyber Expert" in role_names

        # Verify existing users and cases are present
        assert db.query(User).count() >= 1
        assert db.query(Case).count() >= 1

        # Verify new tables exist and can be queried without error
        evidence_count = db.query(Evidence).count()
        hash_count = db.query(EvidenceHash).count()
        assert evidence_count >= 0
        assert hash_count >= 0
    finally:
        db.close()


if __name__ == "__main__":
    tests = [
        test_1_backend_imports_and_routes_registered,
        test_2_real_sha256_generation_and_consistency,
        test_3_sha256_detects_file_modification,
        test_4_member5_integrity_service,
        test_5_member5_tamper_service,
        test_6_forensic_rule_no_original_hash_results_in_unknown,
        test_7_forensic_rule_matching_original_hash_results_in_verified,
        test_8_forensic_rule_different_hashes_results_in_tampered,
        test_9_storage_service_file_categorization,
        test_10_missing_or_invalid_jwt_rejected,
        test_11_authorization_logic_and_case_access,
        test_12_evidence_not_found_raises_404,
        test_13_case_hash_summary_counts,
        test_14_existing_database_connectivity_and_tables_untouched,
    ]

    print("=" * 70)
    print("RUNNING HASH VERIFICATION & INTEGRITY TEST SUITE")
    print("=" * 70)

    passed = 0
    failed = 0

    for test in tests:
        test_name = test.__name__
        try:
            test()
            print(f"PASS: {test_name}")
            passed += 1
        except Exception as e:
            print(f"FAIL: {test_name} - Error: {e}")
            failed += 1

    print("=" * 70)
    print(f"SUMMARY: {passed} passed, {failed} failed")
    print("=" * 70)

    if failed > 0:
        sys.exit(1)

