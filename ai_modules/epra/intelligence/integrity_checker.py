import hashlib


class IntegrityChecker:
    """
    Generates SHA-256 hash of a digital evidence file.
    """

    def generate_hash(self, file_path: str) -> str:

        sha256 = hashlib.sha256()

        with open(file_path, "rb") as file:

            while True:

                chunk = file.read(4096)

                if not chunk:
                    break

                sha256.update(chunk)

        return sha256.hexdigest()

    def verify_integrity(self, file_path: str, expected_hash: str) -> bool:

        current_hash = self.generate_hash(file_path)

        return current_hash == expected_hash