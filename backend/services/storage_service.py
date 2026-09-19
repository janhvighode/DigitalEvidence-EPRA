import os
import mimetypes
from pathlib import Path
from typing import Optional, Tuple
from uuid import uuid4
from fastapi import HTTPException, UploadFile, status


BASE_UPLOAD_DIR = Path("uploads/evidence")


class StorageService:

    @classmethod
    def get_storage_root(cls) -> Path:
        """
        Resolves the durable persistent storage root directory:
        1. Checks EVIDENCE_STORAGE_PATH (or PERSISTENT_STORAGE_DIR) environment variable.
        2. Falls back to standard 'uploads/evidence' relative to workspace/backend root.
        Ensures the root directory exists.
        """
        env_path = os.getenv("EVIDENCE_STORAGE_PATH") or os.getenv("PERSISTENT_STORAGE_DIR")
        if env_path and env_path.strip():
            root = Path(env_path.strip()).resolve()
        else:
            # Fallback for local development and standard repository structure
            cwd_uploads = (Path.cwd() / "uploads" / "evidence").resolve()
            backend_uploads = (Path(__file__).resolve().parent.parent / "uploads" / "evidence").resolve()
            root = cwd_uploads if (Path.cwd() / "uploads").exists() else backend_uploads

        root.mkdir(parents=True, exist_ok=True)
        return root

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
                "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                "application/json",
                "application/xml",
                "text/xml",
                "text/csv"
            ]:
                return "Document"
            elif mime_type in ["application/zip", "application/x-rar-compressed", "application/x-7z-compressed"]:
                return "Archive"

        ext = extension.lower().lstrip(".")
        if ext in ["jpg", "jpeg", "png", "gif", "bmp", "webp"]:
            return "Image"
        elif ext in ["pdf", "doc", "docx", "txt", "xlsx", "xls", "csv", "log", "json", "xml", "tsv", "eml", "msg"]:
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
        Saves an uploaded evidence file to durable persistent storage.
        Returns stable storage reference, original filename, size, and category.
        """
        storage_root = cls.get_storage_root()
        case_dir = storage_root / str(case_id)
        case_dir.mkdir(parents=True, exist_ok=True)

        original_filename = Path(file.filename or "unknown").name
        ext = Path(original_filename).suffix

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

        # Stable relative storage path (case-isolated)
        stable_rel_path = f"uploads/evidence/{case_id}/{unique_name}"
        storage_key = f"{case_id}/{unique_name}"

        return {
            "file_path": stable_rel_path,
            "storage_key": storage_key,
            "physical_path": str(destination).replace("\\", "/"),
            "file_name": original_filename,
            "file_size": total_size,
            "file_type": file_category
        }

    @classmethod
    def resolve_evidence_path(
        cls,
        raw_path: str | Path | None,
        case_id: Optional[int | str] = None,
        storage_key: Optional[str] = None
    ) -> Optional[Path]:
        """
        Safely resolves an evidence file on disk:
        - Prevents directory traversal attacks.
        - Supports storage_key, relative durable paths, and legacy absolute paths.
        - Returns resolved Path if file exists, else None.
        """
        if not raw_path and not storage_key:
            return None

        storage_root = cls.get_storage_root()

        # Potential search roots for safe containment
        allowed_roots = [
            storage_root,
            (Path.cwd() / "uploads" / "evidence").resolve(),
            (Path(__file__).resolve().parent.parent / "uploads" / "evidence").resolve(),
            (Path(__file__).resolve().parent.parent.parent / "uploads" / "evidence").resolve(),
        ]

        def _is_safe(candidate: Path) -> bool:
            for root in allowed_roots:
                try:
                    if candidate.resolve().is_relative_to(root.resolve()):
                        return True
                except (ValueError, AttributeError):
                    pass
            return False

        # 1. Resolve via storage_key if present
        if storage_key:
            clean_key = str(storage_key).strip().replace("\\", "/").lstrip("/")
            if ".." in clean_key.split("/"):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Access denied: Invalid file path traversal"
                )
            candidate = (storage_root / clean_key).resolve()
            if not _is_safe(candidate):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Access denied: Invalid file path traversal"
                )
            if candidate.is_file():
                return candidate

        # 2. Resolve via raw_path
        if raw_path:
            clean_str = str(raw_path).strip().replace("\\", "/")
            if ".." in clean_str.split("/"):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Access denied: Invalid file path traversal"
                )

            # 2a. Check relative to storage_root
            if clean_str.startswith("uploads/evidence/"):
                rel_suffix = clean_str[len("uploads/evidence/"):].lstrip("/")
                candidate = (storage_root / rel_suffix).resolve()
                if not _is_safe(candidate):
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Access denied: Invalid file path traversal"
                    )
                if candidate.is_file():
                    return candidate
            elif clean_str.startswith("uploads/"):
                rel_suffix = clean_str[len("uploads/"):].lstrip("/")
                candidate = (storage_root.parent / rel_suffix).resolve()
                if candidate.is_file():
                    return candidate

            # 2b. Check candidate directly in storage_root / clean_str
            candidate = (storage_root / clean_str).resolve()
            if not _is_safe(candidate):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Access denied: Invalid file path traversal"
                )
            if candidate.is_file():
                return candidate

            # 2c. Check relative to cwd or backend
            for base in [Path.cwd(), Path(__file__).resolve().parent.parent, Path(__file__).resolve().parent.parent.parent]:
                candidate = (base / clean_str).resolve()
                if candidate.is_file():
                    return candidate

            # 2d. Direct absolute path check (legacy records)
            direct = Path(raw_path)
            if direct.is_absolute():
                if direct.exists() and not _is_safe(direct):
                    raise HTTPException(
                        status_code=status.HTTP_403_FORBIDDEN,
                        detail="Access denied: Invalid file path traversal"
                    )
                if direct.is_file():
                    return direct.resolve()

            # 2e. Case-isolated filename fallback within storage_root
            if case_id:
                fname = direct.name
                candidate = (storage_root / str(case_id) / fname).resolve()
                if _is_safe(candidate) and candidate.is_file():
                    return candidate

        return None

    @classmethod
    def get_evidence_binary(
        cls,
        evidence,
        case=None
    ) -> Tuple[Path, str, str]:
        """
        Retrieves the physical evidence file from persistent storage.
        Raises HTTP 404 with clear message if physical file is missing.
        Returns (resolved_path, original_filename, mime_type).
        """
        case_id = case.id if case else getattr(evidence, "case_id", None)
        storage_key = getattr(evidence, "storage_key", None)
        resolved_path = cls.resolve_evidence_path(
            raw_path=getattr(evidence, "file_path", None),
            case_id=case_id,
            storage_key=storage_key
        )

        if not resolved_path or not resolved_path.is_file():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Evidence file is not available in persistent storage (not found on disk)."
            )

        file_name = getattr(evidence, "file_name", "evidence.bin")
        mime_type, _ = mimetypes.guess_type(file_name)
        mime_type = mime_type or "application/octet-stream"

        return resolved_path, file_name, mime_type

