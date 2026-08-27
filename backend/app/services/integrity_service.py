class IntegrityService:

    @staticmethod
    def verify_integrity(original_hash, current_hash):
        """
        Verify evidence integrity.
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