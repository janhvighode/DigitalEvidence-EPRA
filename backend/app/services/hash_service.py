import hashlib
from pathlib import Path
from datetime import datetime


class HashService:

    @staticmethod
    def generate_sha256(file_path: str) -> str:
        """
        Generate SHA-256 hash for a single evidence file.
        """

        path = Path(file_path)

        if not path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        if not path.is_file():
            raise ValueError(f"Path is not a file: {file_path}")

        sha256_hash = hashlib.sha256()

        # Read file in chunks so large evidence files
        # can also be processed efficiently.
        with open(path, "rb") as file:
            while chunk := file.read(1024 * 1024):
                sha256_hash.update(chunk)

        return sha256_hash.hexdigest()

    @staticmethod
    def generate_file_hash_record(
        evidence_id: int,
        file_path: str
    ) -> dict:
        """
        Generate SHA-256 hash and return complete
        evidence hash information.
        """

        path = Path(file_path)

        sha256 = HashService.generate_sha256(file_path)

        return {
            "evidence_id": evidence_id,
            "file_name": path.name,
            "file_path": str(path),
            "sha256_hash": sha256,
            "created_at": datetime.now().isoformat()
        }

    @staticmethod
    def generate_multiple_hashes(files: list) -> list:
        """
        Generate SHA-256 hashes for multiple evidence files.

        Expected input:

        [
            {
                "evidence_id": 101,
                "file_path": "app/uploads/evidence1.pdf"
            },
            {
                "evidence_id": 102,
                "file_path": "app/uploads/image.jpg"
            }
        ]
        """

        results = []

        for file in files:

            record = HashService.generate_file_hash_record(
                evidence_id=file["evidence_id"],
                file_path=file["file_path"]
            )

            results.append(record)

        return results