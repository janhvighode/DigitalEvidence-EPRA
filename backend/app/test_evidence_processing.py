from app.services.evidence_processing_service import (
    EvidenceProcessingService
)


def run_test():

    evidence_id = 101
    file_path = "app/uploads/CASE-2026-001.pdf"

    print("=" * 70)
    print("DIGITAL EVIDENCE - COMPLETE PROCESSING TEST")
    print("=" * 70)

    result = EvidenceProcessingService.process_evidence(
        evidence_id=evidence_id,
        file_path=file_path
    )

    if not result["success"]:

        print("\nPROCESSING FAILED")
        print(result)

        return

    print("\nEvidence ID :", result["evidence_id"])

    print("\n--- VALIDATION ---")
    print("Status :", result["validation"]["status"])

    print("\n--- CLASSIFICATION ---")
    print("Type   :", result["classification"]["evidence_type"])
    print("MIME   :", result["classification"]["mime_type"])

    print("\n--- METADATA ---")
    print("File   :", result["metadata"]["file_name"])
    print("Size   :", result["metadata"]["file_size_bytes"], "bytes")
    print("Ext    :", result["metadata"]["file_extension"])

    print("\n--- SHA-256 ---")
    print("Hash   :", result["hash"]["sha256_hash"])

    print("\n" + "=" * 70)
    print("COMPLETE EVIDENCE PROCESSING TEST SUCCESS")
    print("=" * 70)


if __name__ == "__main__":
    run_test()