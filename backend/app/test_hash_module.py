import sys
import tempfile
from pathlib import Path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.services.file_hash_service import FileHashService
from app.services.hash_manifest_service import HashManifestService


def run_test():
    print("=" * 70)
    print("DIGITAL EVIDENCE - HASH MANIFEST & FORMAT VALIDATION TEST")
    print("=" * 70)

    # 1. SHA-256 Format Validation (without local hash calculation)
    valid_hash = "a3f5e8d9c7b2e4f1a6c9d3e8b7f5a2c4d8e9f7b6c5d4a3e2f1b0c9d8e7f6a5b4"
    invalid_hash = "not-a-valid-sha256-hash"

    assert FileHashService.is_valid_sha256(valid_hash) is True
    assert FileHashService.is_valid_sha256(invalid_hash) is False
    assert FileHashService.is_valid_sha256(None) is False
    print("\n--- SHA-256 FORMAT VALIDATION ---")
    print("Valid 64-hex Check   : PASS")
    print("Malformed Hash Check : PASS (Rejected)")

    # 2. Hash Manifest Creation from Backend-Supplied Hash Records
    evidence_records = [
        {
            "evidence_id": "EV-101",
            "file_name": "transaction_screenshot.png",
            "sha256_hash": valid_hash,
            "verification_status": "Verified",
            "verification_source": "Integrated Backend SHA-256 Verifier"
        }
    ]

    manifest = HashManifestService.create_manifest("CASE-2026-001", evidence_records)

    assert manifest["case_id"] == "CASE-2026-001"
    assert manifest["hash_algorithm"] == "SHA-256"
    assert manifest["total_evidence_files"] == 1
    assert manifest["evidence"][0]["evidence_id"] == "EV-101"
    assert manifest["evidence"][0]["sha256_hash"] == valid_hash

    print("\n--- HASH MANIFEST CREATION ---")
    print("Case ID        :", manifest["case_id"])
    print("Hash Algorithm :", manifest["hash_algorithm"])
    print("Total Evidence :", manifest["total_evidence_files"])
    print("Evidence Hash  :", manifest["evidence"][0]["sha256_hash"])

    # 3. Save Manifest to Isolated Temporary Directory
    with tempfile.TemporaryDirectory() as tmp_dir:
        saved_path = HashManifestService.save_manifest(manifest, output_directory=Path(tmp_dir))
        assert Path(saved_path).exists()
        assert Path(saved_path).stat().st_size > 50

    print("\n" + "=" * 70)
    print("HASH MANIFEST TEST SUCCESS (ASSERTIONS PASSED)")
    print("=" * 70)


if __name__ == "__main__":
    run_test()