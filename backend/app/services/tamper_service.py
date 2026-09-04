from datetime import datetime


class TamperService:

    @staticmethod
    def detect_tampering(original_hash, current_hash):

        if original_hash == current_hash:

            return {
                "status": "Original",
                "message": "Evidence is authentic.",
                "checked_at": datetime.now().strftime("%d-%m-%Y %H:%M:%S")
            }

        return {
            "status": "Tampered",
            "message": "Evidence integrity compromised.",
            "checked_at": datetime.now().strftime("%d-%m-%Y %H:%M:%S")
        }