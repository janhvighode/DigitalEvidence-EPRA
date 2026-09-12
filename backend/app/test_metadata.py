import sys
from pathlib import Path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.services.metadata_service import MetadataService


def run_test():
    file_path = Path(__file__).parent / "uploads" / "CASE-2026-001.pdf"
    if not file_path.exists():
        file_path = Path(__file__).parent / "test_evidence.txt"

    print("=" * 70)
    print("DIGITAL EVIDENCE - METADATA EXTRACTION TEST")
    print("=" * 70)

    metadata = MetadataService.extract_metadata(str(file_path))

    for key, value in metadata.items():
        print(f"{key.replace('_', ' ').title():25}: {value}")

    # Assertions
    assert metadata["file_name"] == file_path.name
    assert metadata["file_size_bytes"] == file_path.stat().st_size
    assert "filesystem_ctime" in metadata
    assert "filesystem_ctime_source" in metadata
    assert "filesystem_mtime" in metadata
    assert "filesystem_mtime_source" in metadata

    print("\n" + "=" * 70)
    print("METADATA EXTRACTION TEST SUCCESS (ASSERTIONS PASSED)")
    print("=" * 70)


if __name__ == "__main__":
    run_test()