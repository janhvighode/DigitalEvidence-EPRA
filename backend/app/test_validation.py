from app.services.evidence_validation_service import (
    EvidenceValidationService
)


def run_test():

    file_path = "app/uploads/CASE-2026-001.pdf"

    print("=" * 70)
    print("DIGITAL EVIDENCE - VALIDATION TEST")
    print("=" * 70)

    result = EvidenceValidationService.validate_file(
        file_path
    )

    print("\nStatus  :", result["status"])
    print("Valid   :", result["valid"])
    print("Message :", result["message"])

    if result["valid"]:

        print("File    :", result["file_name"])
        print("Size    :", result["file_size_bytes"], "bytes")

        print("\n" + "=" * 70)
        print("EVIDENCE VALIDATION TEST SUCCESS")
        print("=" * 70)

    else:

        print("\nEVIDENCE VALIDATION TEST FAILED")


if __name__ == "__main__":
    run_test()