from pathlib import Path


class EvidenceValidationService:

    @staticmethod
    def validate_file(file_path: str, allow_empty: bool = True) -> dict:
        """
        Validate an evidence file before processing.
        Explicitly distinguishes empty file policy from file access errors:
        - 0-byte files have a defined SHA-256 digest (e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855)
        - If allow_empty=True, returns valid=True with status EMPTY_FILE_NOTED.
        - If allow_empty=False, returns valid=False with status EMPTY_FILE_REJECTED.
        """
        path = Path(file_path)

        # Check existence
        if not path.exists():
            return {
                "valid": False,
                "status": "FILE_NOT_FOUND",
                "message": f"Evidence file does not exist at {file_path}."
            }

        # Check file
        if not path.is_file():
            return {
                "valid": False,
                "status": "INVALID_PATH",
                "message": "Provided path is a directory or special device, not a regular file."
            }

        # Check readability
        try:
            with open(path, "rb") as file:
                file.read(1)
        except PermissionError:
            return {
                "valid": False,
                "status": "ACCESS_DENIED",
                "message": "Evidence file cannot be read due to permission restrictions."
            }
        except Exception as e:
            return {
                "valid": False,
                "status": "READ_ERROR",
                "message": f"Error reading evidence file: {str(e)}"
            }

        # Check empty file
        is_empty = (path.stat().st_size == 0)
        if is_empty:
            if allow_empty:
                return {
                    "valid": True,
                    "status": "EMPTY_FILE_NOTED",
                    "message": "Evidence file is 0 bytes. Baseline SHA-256 can be computed; payload is empty.",
                    "file_name": path.name,
                    "file_size_bytes": 0,
                    "is_empty": True
                }
            else:
                return {
                    "valid": False,
                    "status": "EMPTY_FILE_REJECTED",
                    "message": "Evidence file policy rejects 0-byte files.",
                    "file_name": path.name,
                    "file_size_bytes": 0,
                    "is_empty": True
                }

        return {
            "valid": True,
            "status": "VALID",
            "message": "Evidence file is valid and ready for processing.",
            "file_name": path.name,
            "file_size_bytes": path.stat().st_size,
            "is_empty": False
        }
