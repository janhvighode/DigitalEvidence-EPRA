class DuplicateDetector:
    """
    Detects duplicate evidence
    using SHA-256 hashes.
    """

    def is_duplicate(self, hash1: str, hash2: str) -> bool:
        """
        Returns True if two hashes are identical.
        """

        return hash1 == hash2

    def find_duplicates(self, hashes: list) -> list:
        """
        Returns duplicate hashes.
        """

        seen = set()
        duplicates = []

        for file_hash in hashes:

            if file_hash in seen:
                duplicates.append(file_hash)

            else:
                seen.add(file_hash)

        return duplicates