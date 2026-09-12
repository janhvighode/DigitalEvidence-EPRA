import sys
from pathlib import Path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.services.evidence_classifier import EvidenceClassifier


def run_test():
    file_path = Path(__file__).parent / "uploads" / "CASE-2026-001.pdf"
    if not file_path.exists():
        file_path = Path(__file__).parent / "test_evidence.txt"

    print("=" * 70)
    print("DIGITAL EVIDENCE - FILE CLASSIFICATION TEST")
    print("=" * 70)

    result = EvidenceClassifier.classify(str(file_path))

    print("\nFile Name   :", result["file_name"])
    print("Extension   :", result["extension"])
    print("MIME Type   :", result["mime_type"])
    print("Evidence Type:", result["evidence_type"])

    assert result["file_name"] == file_path.name
    assert result["extension"] == file_path.suffix.lower()
    assert result["evidence_type"] in ("PDF", "DOCUMENT", "IMAGE", "VIDEO", "AUDIO", "SPREADSHEET", "ARCHIVE", "OTHER")

    print("\n" + "=" * 70)
    print("FILE CLASSIFICATION TEST SUCCESS (ASSERTIONS PASSED)")
    print("=" * 70)


if __name__ == "__main__":
    run_test()