import sys
from pathlib import Path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.services.evidence_validation_service import EvidenceValidationService


def run_test():
    file_path = Path(__file__).parent / "uploads" / "CASE-2026-001.pdf"
    if not file_path.exists():
        file_path = Path(__file__).parent / "test_evidence.txt"

    print("=" * 70)
    print("DIGITAL EVIDENCE - VALIDATION TEST")
    print("=" * 70)

    result = EvidenceValidationService.validate_file(str(file_path))

    print("\nStatus  :", result["status"])
    print("Valid   :", result["valid"])
    print("Message :", result["message"])

    assert result["valid"] is True, "Valid file must pass validation"
    assert result["file_name"] == file_path.name
    assert result["file_size_bytes"] == file_path.stat().st_size

    # Nonexistent file check
    missing = EvidenceValidationService.validate_file("nonexistent_path.bin")
    assert missing["valid"] is False
    assert missing["status"] == "FILE_NOT_FOUND"

    print("\n" + "=" * 70)
    print("EVIDENCE VALIDATION TEST SUCCESS (ASSERTIONS PASSED)")
    print("=" * 70)


if __name__ == "__main__":
    run_test()