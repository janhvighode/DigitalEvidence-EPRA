from pathlib import Path


class EvidenceValidationService:

    @staticmethod
    def validate_file(file_path: str) -> dict:
        """
        Validate an evidence file before processing.
        """

        path = Path(file_path)

        # Check existence
        if not path.exists():
            return {
                "valid": False,
                "status": "FILE_NOT_FOUND",
                "message": "Evidence file does not exist."
            }

        # Check file
        if not path.is_file():
            return {
                "valid": False,
                "status": "INVALID_PATH",
                "message": "Provided path is not a file."
            }

        # Check empty file
        if path.stat().st_size == 0:
            return {
                "valid": False,
                "status": "EMPTY_FILE",
                "message": "Evidence file is empty."
            }

        # Check readability
        try:
            with open(path, "rb") as file:
                file.read(1)

        except PermissionError:
            return {
                "valid": False,
                "status": "ACCESS_DENIED",
                "message": "Evidence file cannot be read."
            }

        return {
            "valid": True,
            "status": "VALID",
            "message": "Evidence file is valid and ready for processing.",
            "file_name": path.name,
            "file_size_bytes": path.stat().st_size
        }