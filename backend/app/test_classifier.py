from app.services.evidence_classifier import EvidenceClassifier


def run_test():

    files = [
        "app/uploads/CASE-2026-001.pdf"
    ]

    print("=" * 70)
    print("DIGITAL EVIDENCE - FILE CLASSIFICATION TEST")
    print("=" * 70)

    try:

        for file_path in files:

            result = EvidenceClassifier.classify(file_path)

            print("\nFile Name   :", result["file_name"])
            print("Extension   :", result["extension"])
            print("MIME Type   :", result["mime_type"])
            print("Evidence Type:", result["evidence_type"])

        print("\n" + "=" * 70)
        print("FILE CLASSIFICATION TEST SUCCESS")
        print("=" * 70)

    except Exception as e:

        print("\nFILE CLASSIFICATION TEST FAILED")
        print("Error:", str(e))


if __name__ == "__main__":
    run_test()