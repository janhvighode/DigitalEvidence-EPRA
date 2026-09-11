import json
from pathlib import Path
from datetime import datetime, timezone


class HashManifestService:

    @staticmethod
    def create_manifest(
        case_id: str,
        evidence_records: list
    ) -> dict:
        """
        Create a structured hash manifest for
        digital evidence files.
        """

        manifest = {
            "case_id": case_id,
            "manifest_type": "Digital Evidence Hash Manifest",
            "hash_algorithm": "SHA-256",
            "generated_at": datetime.now(
                timezone.utc
            ).isoformat(),
            "total_evidence_files": len(evidence_records),
            "evidence": evidence_records
        }

        return manifest

    @staticmethod
    def save_manifest(
        manifest: dict,
        output_directory: str = "app/uploads/hash_manifests"
    ) -> str:
        """
        Save hash manifest as a JSON file.
        """

        directory = Path(output_directory)
        directory.mkdir(
            parents=True,
            exist_ok=True
        )

        case_id = manifest.get(
            "case_id",
            "UNKNOWN_CASE"
        )

        timestamp = datetime.now(
            timezone.utc
        ).strftime("%Y%m%d_%H%M%S")

        file_name = (
            f"{case_id}_hash_manifest_{timestamp}.json"
        )

        file_path = directory / file_name

        with open(
            file_path,
            "w",
            encoding="utf-8"
        ) as file:

            json.dump(
                manifest,
                file,
                indent=4
            )

        return str(file_path)