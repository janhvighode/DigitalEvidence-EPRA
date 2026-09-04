import hashlib
from pathlib import Path


class FileHashService:

    @staticmethod
    def generate_sha256(file_path: str) -> str:
        """
        Generate SHA-256 hash for any file.
        """

        path = Path(file_path)

        if not path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        sha256 = hashlib.sha256()

        with open(path, "rb") as file:
            while chunk := file.read(1024 * 1024):
                sha256.update(chunk)

        return sha256.hexdigest()