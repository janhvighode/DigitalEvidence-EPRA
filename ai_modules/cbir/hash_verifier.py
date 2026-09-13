# ============================================================
# Digital Evidence EPRA
# Module : CBIR / Forensic Integrity
# File   : hash_verifier.py
# Purpose: Cryptographic hash (SHA-256) computation and exact
#          duplicate verification for digital evidence.
# ============================================================

import os
import sys

# Shared Deepak Cryptographic SHA-256 Service
PROJECT_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
for p in [
    PROJECT_ROOT,
    os.path.join(PROJECT_ROOT, "backend"),
    os.path.join(PROJECT_ROOT, "backend", "app"),
    os.path.join(PROJECT_ROOT, "backend", "app", "services"),
    os.path.join(PROJECT_ROOT, "backend", "services")
]:
    if p not in sys.path:
        sys.path.insert(0, p)

try:
    from backend.app.services.hash_service import HashService
except ImportError:
    try:
        from backend.services.hash_service import HashService
    except ImportError:
        try:
            from app.services.hash_service import HashService
        except ImportError:
            from hash_service import HashService

try:
    from backend.app.services.file_hash_service import FileHashService
except ImportError:
    try:
        from backend.services.file_hash_service import FileHashService
    except ImportError:
        FileHashService = None


def compute_sha256(file_path, chunk_size=65536):
    """
    Compute the SHA-256 cryptographic hash of an evidence file.
    Delegates directly to Deepak's shared HashService.generate_sha256.

    In digital forensics (ISO/IEC 27037), SHA-256 provides a
    mathematically verified integrity check. Identical hashes
    prove exact bit-for-bit file duplicate status.

    Parameters
    ----------
    file_path : str
        Path to the evidence file.
    chunk_size : int, optional
        Ignored; buffer chunking handled inside shared HashService.

    Returns
    -------
    str or None
        64-character lowercase hex SHA-256 digest, or None on error.
    """
    if not file_path or not os.path.isfile(file_path):
        return None

    try:
        digest = HashService.generate_sha256(str(file_path))
        if digest and FileHashService is not None:
            if not FileHashService.is_valid_sha256(digest):
                return None
        return digest.lower() if digest else None
    except Exception as error:
        print(f"Error computing SHA-256 via shared HashService for {file_path}: {error}")
        return None


def are_exact_duplicates(file_path_1, file_path_2):
    """
    Check if two evidence files are exact cryptographic duplicates.

    Returns
    -------
    tuple
        (is_duplicate: bool, hash_1: str or None, hash_2: str or None)
    """
    hash1 = compute_sha256(file_path_1)
    hash2 = compute_sha256(file_path_2)

    if hash1 is None or hash2 is None:
        return False, hash1, hash2

    return (hash1 == hash2), hash1, hash2


if __name__ == "__main__":
    print("=" * 60)
    print("DIGITAL EVIDENCE EPRA - SHA-256 INTEGRITY VERIFIER")
    print("=" * 60)

    test_ev1 = "test_cases/CASE_TEST_01/EV_TEST_01.jpg"
    test_ev3 = "test_cases/CASE_TEST_01/EV_TEST_03.jpg"
    test_ev2 = "test_cases/CASE_TEST_01/EV_TEST_02.jpg"

    if os.path.exists(test_ev1) and os.path.exists(test_ev3):
        dup, h1, h3 = are_exact_duplicates(test_ev1, test_ev3)
        print(f"\nEV_TEST_01 hash : {h1}")
        print(f"EV_TEST_03 hash : {h3}")
        print(f"Exact Duplicate : {dup}")

    if os.path.exists(test_ev1) and os.path.exists(test_ev2):
        dup, h1, h2 = are_exact_duplicates(test_ev1, test_ev2)
        print(f"\nEV_TEST_01 hash : {h1}")
        print(f"EV_TEST_02 hash : {h2}")
        print(f"Exact Duplicate : {dup}")
