from app.services.hash_service import HashService
from app.services.tamper_service import TamperService


def run_test():

    file_path = "app/test_evidence.txt"

    # Generate original hash
    original_hash = HashService.generate_sha256(file_path)

    print("=" * 60)
    print("TAMPER DETECTION TEST")
    print("=" * 60)

    print("\nOriginal SHA-256:")
    print(original_hash)

    # Test 1: Original file
    current_hash = HashService.generate_sha256(file_path)

    result = TamperService.detect_tampering(
        original_hash,
        current_hash
    )

    print("\nTest 1 - Original Evidence")
    print("Status :", result["status"])
    print("Message:", result["message"])
    print("Checked:", result["checked_at"])

    # Test 2: Simulated modified hash
    modified_hash = "0000000000000000000000000000000000000000000000000000000000000000"

    result = TamperService.detect_tampering(
        original_hash,
        modified_hash
    )

    print("\nTest 2 - Modified Evidence")
    print("Status :", result["status"])
    print("Message:", result["message"])
    print("Checked:", result["checked_at"])

    # Validation
    if result["status"] == "Tampered":

        print("\n" + "=" * 60)
        print("TAMPER DETECTION TEST SUCCESS")
        print("=" * 60)

    else:

        print("\nTAMPER DETECTION TEST FAILED")


if __name__ == "__main__":
    run_test()