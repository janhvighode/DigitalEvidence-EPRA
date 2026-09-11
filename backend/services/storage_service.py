import os
import mimetypes
from pathlib import Path
from uuid import uuid4
from fastapi import UploadFile


BASE_UPLOAD_DIR = Path("uploads/evidence")


class StorageService:

    @staticmethod
    def _categorize_file_type(mime_type: str | None, extension: str) -> str:
        if mime_type:
            if mime_type.startswith("image/"):
                return "Image"
            elif mime_type.startswith("video/"):
                return "Video"
            elif mime_type.startswith("audio/"):
                return "Audio"
            elif mime_type in ["application/pdf"]:
                return "PDF Document"
            elif mime_type in [
                "application/msword",
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
                "text/plain",
                "application/vnd.ms-excel",
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            ]:
                return "Document"
            elif mime_type in ["application/zip", "application/x-rar-compressed", "application/x-7z-compressed"]:
                return "Archive"

        ext = extension.lower().lstrip(".")
        if ext in ["jpg", "jpeg", "png", "gif", "bmp", "webp"]:
            return "Image"
        elif ext in ["pdf", "doc", "docx", "txt", "xlsx", "xls", "csv"]:
            return "Document"
        elif ext in ["mp4", "avi", "mov", "mkv"]:
            return "Video"
        elif ext in ["mp3", "wav", "aac"]:
            return "Audio"
        elif ext in ["zip", "rar", "7z", "tar", "gz"]:
            return "Archive"

        return mime_type or "Unknown"

    @classmethod
    async def save_uploaded_file(
        cls,
        file: UploadFile,
        case_id: int | str
    ) -> dict:
        """
        Saves an uploaded evidence file to isolated local disk storage.
        Returns stored file path, original name, size, and category.
        """
        original_filename = Path(file.filename or "unknown").name
        ext = Path(original_filename).suffix

        # Ensure directory exists for specific case
        case_dir = BASE_UPLOAD_DIR / str(case_id)
        case_dir.mkdir(parents=True, exist_ok=True)

        # Unique stored filename to avoid collision or overwrite
        unique_name = f"{uuid4().hex}_{original_filename}"
        destination = case_dir / unique_name

        total_size = 0
        with open(destination, "wb") as buffer:
            while chunk := await file.read(1024 * 1024):
                buffer.write(chunk)
                total_size += len(chunk)

        # Detect MIME type and friendly category
        mime_type, _ = mimetypes.guess_type(original_filename)
        file_category = cls._categorize_file_type(mime_type, ext)

        return {
            "file_path": str(destination).replace("\\", "/"),
            "file_name": original_filename,
            "file_size": total_size,
            "file_type": file_category
        }
