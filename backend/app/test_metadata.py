from app.services.metadata_service import MetadataService


def run_test():

    file_path = "app/uploads/CASE-2026-001.pdf"

    print("=" * 70)
    print("DIGITAL EVIDENCE - METADATA EXTRACTION TEST")
    print("=" * 70)

    try:

        metadata = MetadataService.extract_metadata(file_path)

        for key, value in metadata.items():
            print(f"{key.replace('_', ' ').title():20}: {value}")

        print("\n" + "=" * 70)
        print("METADATA EXTRACTION TEST SUCCESS")
        print("=" * 70)

    except Exception as e:

        print("\nMETADATA EXTRACTION TEST FAILED")
        print("Error:", str(e))


if __name__ == "__main__":
    run_test()