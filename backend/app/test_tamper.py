import sys
from pathlib import Path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from app.services.backend_adapter import map_backend_verification_status


def run_test():
    print("=" * 60)
    print("VERIFICATION STATUS MAPPING TEST (RETAINED MEMBER 5)")
    print("=" * 60)

    # Test 1: Verified / MATCH
    assert map_backend_verification_status("Verified") == "Verified"
    assert map_backend_verification_status("MATCH") == "Verified"
    assert map_backend_verification_status("verified") == "Verified"
    print("Outcome for 'MATCH'    :", map_backend_verification_status("MATCH"))

    # Test 2: Tampered / MISMATCH
    assert map_backend_verification_status("Tampered") == "Tampered"
    assert map_backend_verification_status("MISMATCH") == "Tampered"
    assert map_backend_verification_status("tampered") == "Tampered"
    print("Outcome for 'MISMATCH' :", map_backend_verification_status("MISMATCH"))

    # Test 3: Pending
    assert map_backend_verification_status("pending") == "Pending"
    assert map_backend_verification_status("Pending") == "Pending"
    print("Outcome for 'pending'  :", map_backend_verification_status("pending"))

    # Test 4: Unknown and Error
    assert map_backend_verification_status(None) == "Unknown"
    assert map_backend_verification_status("unknown") == "Unknown"
    assert map_backend_verification_status("error") == "Error"
    print("Outcome for None       :", map_backend_verification_status(None))
    print("Outcome for 'error'    :", map_backend_verification_status("error"))

    print("\n" + "=" * 60)
    print("VERIFICATION MAPPING TEST SUCCESS (ALL ASSERTIONS PASSED)")
    print("=" * 60)


if __name__ == "__main__":
    run_test()