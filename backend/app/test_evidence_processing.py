import sys
from pathlib import Path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.services.evidence_validation_service import EvidenceValidationService
from app.services.evidence_classifier import EvidenceClassifier
from app.services.metadata_service import MetadataService


def run_test():
    file_path = Path(__file__).parent / "uploads" / "CASE-2026-001.pdf"
    if not file_path.exists():
        file_path = Path(__file__).parent / "test_evidence.txt"

    print("=" * 70)
    print("DIGITAL EVIDENCE - EVIDENCE PROCESSING TEST (METADATA + CLASSIFICATION)")
    print("=" * 70)

    val = EvidenceValidationService.validate_file(str(file_path))
    classification = EvidenceClassifier.classify(str(file_path))
    metadata = MetadataService.extract_metadata(str(file_path))

    assert val["valid"] is True, f"Validation failed: {val.get('message')}"
    assert classification["file_name"] == file_path.name
    assert classification["evidence_type"] in ("PDF", "DOCUMENT", "IMAGE", "VIDEO", "AUDIO", "SPREADSHEET", "ARCHIVE", "OTHER")
    assert metadata["file_name"] == file_path.name
    assert metadata["file_size_bytes"] == file_path.stat().st_size
    assert "filesystem_ctime" in metadata
    assert "filesystem_mtime" in metadata

    print("\nEvidence File :", file_path.name)
    print("\n--- VALIDATION ---")
    print("Status :", val["status"])
    print("\n--- CLASSIFICATION ---")
    print("Type   :", classification["evidence_type"])
    print("MIME   :", classification["mime_type"])
    print("\n--- METADATA ---")
    print("File   :", metadata["file_name"])
    print("Size   :", metadata["file_size_bytes"], "bytes")

    print("\n" + "=" * 70)
    print("COMPLETE EVIDENCE PROCESSING TEST SUCCESS (ASSERTIONS PASSED)")
    print("=" * 70)


if __name__ == "__main__":
    run_test()