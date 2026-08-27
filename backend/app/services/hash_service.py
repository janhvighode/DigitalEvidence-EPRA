import hashlib
from pathlib import Path


class HashService:
    @staticmethod
    def generate_sha256(file_path: str) -> str:
        """
        Generate SHA-256 hash for a file.

        Args:
            file_path (str): Path of the evidence file.

        Returns:
            str: SHA-256 hash in hexadecimal format.
        """

        # Check if file exists
        path = Path(file_path)

        if not path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")

        # Create SHA-256 object
        sha256_hash = hashlib.sha256()

        # Read file in binary mode
        with open(path, "rb") as file:

            # Read file in 4KB chunks
            while chunk := file.read(4096):
                sha256_hash.update(chunk)

        # Return hexadecimal hash
        return sha256_hash.hexdigest()