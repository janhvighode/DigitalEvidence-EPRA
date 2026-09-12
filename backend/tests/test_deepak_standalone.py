import os
import sys
from pathlib import Path

# Add project root and backend dir to sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from services.metadata_service import MetadataService
from services.evidence_classifier import EvidenceClassifier
from services.evidence_validation_service import EvidenceValidationService


def test_deepak_original_metadata_extraction():
    """Matches Deepak's backend/app/test_metadata.py."""
    sample_file = backend_dir / "uploads" / "test_deepak_evidence.txt"
    sample_file.parent.mkdir(parents=True, exist_ok=True)
    sample_file.write_text("Digital evidence test content for Member 5 metadata extraction.", encoding="utf-8")

    metadata = MetadataService.extract_metadata(str(sample_file))

    assert metadata["file_name"] == sample_file.name
    assert metadata["file_size_bytes"] == sample_file.stat().st_size
    assert "filesystem_ctime" in metadata
    assert "filesystem_ctime_source" in metadata
    assert "filesystem_mtime" in metadata
    assert "filesystem_mtime_source" in metadata
    print("PASS: test_deepak_original_metadata_extraction")


def test_deepak_original_classifier():
    """Matches Deepak's backend/app/test_classifier.py."""
    sample_file = backend_dir / "uploads" / "test_deepak_evidence.txt"
    result = EvidenceClassifier.classify(str(sample_file))

    assert result["file_name"] == sample_file.name
    assert result["extension"] == sample_file.suffix.lower()
    assert result["evidence_type"] in ("PDF", "DOCUMENT", "IMAGE", "VIDEO", "AUDIO", "SPREADSHEET", "ARCHIVE", "OTHER")
    print("PASS: test_deepak_original_classifier")


def test_deepak_original_validation():
    """Matches Deepak's backend/app/test_validation.py."""
    sample_file = backend_dir / "uploads" / "test_deepak_evidence.txt"
    result = EvidenceValidationService.validate_file(str(sample_file))

    assert result["valid"] is True, "Valid file must pass validation"
    assert result["file_name"] == sample_file.name
    assert result["file_size_bytes"] == sample_file.stat().st_size

    missing = EvidenceValidationService.validate_file("nonexistent_deepak_file.bin")
    assert missing["valid"] is False
    assert missing["status"] == "FILE_NOT_FOUND"
    print("PASS: test_deepak_original_validation")


if __name__ == "__main__":
    print("\n--- RUNNING DEEPAK'S STANDALONE TEST SUITE ---")
    test_deepak_original_metadata_extraction()
    test_deepak_original_classifier()
    test_deepak_original_validation()
    print("\nALL DEEPAK STANDALONE TESTS PASSED!")
