from app.services.hash_service import HashService


def run_test():

    # Simulated files fetched from database
    # Integration ke time ye data actual database se aayega.
    evidence_files = [
        {
            "evidence_id": 101,
            "file_path": "app/uploads/CASE-2026-001.pdf"
        }
    ]

    print("=" * 70)
    print("DIGITAL EVIDENCE - SHA-256 HASH GENERATION")
    print("=" * 70)

    try:

        hash_records = HashService.generate_multiple_hashes(
            evidence_files
        )

        for record in hash_records:

            print("\nEvidence ID :", record["evidence_id"])
            print("File Name   :", record["file_name"])
            print("File Path   :", record["file_path"])
            print("SHA-256     :", record["sha256_hash"])
            print("Created At  :", record["created_at"])

        print("\n" + "=" * 70)
        print("HASH GENERATION TEST SUCCESS")
        print("=" * 70)

    except Exception as e:

        print("\nHASH GENERATION TEST FAILED")
        print("Error:", str(e))


if __name__ == "__main__":
    run_test()