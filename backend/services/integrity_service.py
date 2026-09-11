class IntegrityService:

    @staticmethod
    def verify_integrity(original_hash: str, current_hash: str) -> dict:
        """
        Verify evidence integrity by comparing original reference hash
        against currently generated SHA-256 hash.
        """

        if original_hash == current_hash:

            return {
                "status": "Verified",
                "tampered": False
            }

        return {
            "status": "Tampered",
            "tampered": True
        }
