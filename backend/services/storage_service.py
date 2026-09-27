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
        - Checks across all persistent storage roots (cwd uploads, backend uploads, project root).
        - Handles deployment prefixes (e.g. Render /opt/render/... paths).
        - Supports numeric case ID and string case code folder matching.
        - Handles UUID-prefixed and original filename matching.
        - Returns resolved Path if file exists, else None.
        """
        if not raw_path and not storage_key:
            return None

        storage_root = cls.get_storage_root()
        backend_dir = Path(__file__).resolve().parent.parent
        project_root = backend_dir.parent

        allowed_roots = [
            storage_root,
            (Path.cwd() / "uploads" / "evidence").resolve(),
            (backend_dir / "uploads" / "evidence").resolve(),
            (project_root / "uploads" / "evidence").resolve(),
            (Path.cwd() / "uploads").resolve(),
            (backend_dir / "uploads").resolve(),
            (project_root / "uploads").resolve(),
        ]
        unique_roots: list[Path] = []
        for r in allowed_roots:
            if r not in unique_roots and r.exists():
                unique_roots.append(r)
        if storage_root not in unique_roots:
            unique_roots.insert(0, storage_root)

        def _is_safe(candidate: Path) -> bool:
            for root in unique_roots:
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
            for root in unique_roots:
                candidate = (root / clean_key).resolve()
                if _is_safe(candidate) and candidate.is_file():
                    return candidate

        # 2. Resolve via raw_path
        if raw_path:
            clean_str = str(raw_path).strip().replace("\\", "/")
            if ".." in clean_str.split("/"):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail="Access denied: Invalid file path traversal"
                )

            # 2a. Check if clean_str contains 'uploads/evidence/' anywhere
            if "uploads/evidence/" in clean_str:
                rel_suffix = clean_str.split("uploads/evidence/")[-1].lstrip("/")
                for root in unique_roots:
                    candidate = (root / rel_suffix).resolve()
                    if _is_safe(candidate) and candidate.is_file():
                        return candidate
                    candidate_ev = (root / "evidence" / rel_suffix).resolve()
                    if _is_safe(candidate_ev) and candidate_ev.is_file():
                        return candidate_ev

            # 2b. Check if clean_str contains 'uploads/' anywhere
            if "uploads/" in clean_str:
                rel_suffix = clean_str.split("uploads/")[-1].lstrip("/")
                for root in unique_roots:
                    candidate = (root / rel_suffix).resolve()
                    if _is_safe(candidate) and candidate.is_file():
                        return candidate
                    if root.name == "evidence":
                        candidate_parent = (root.parent / rel_suffix).resolve()
                        if _is_safe(candidate_parent) and candidate_parent.is_file():
                            return candidate_parent

            # 2c. Check candidate directly in unique_roots
            for root in unique_roots:
                candidate = (root / clean_str.lstrip("/")).resolve()
                if _is_safe(candidate) and candidate.is_file():
                    return candidate

            # 2d. Check relative to cwd or backend or project_root
            for base in [Path.cwd(), backend_dir, project_root]:
                candidate = (base / clean_str.lstrip("/")).resolve()
                if _is_safe(candidate) and candidate.is_file():
                    return candidate

            # 2e. Direct absolute path check (legacy local records)
            direct = Path(raw_path)
            try:
                if direct.is_absolute():
                    if direct.is_file() and _is_safe(direct):
                        return direct.resolve()
            except Exception:
                pass

            # 2f. Case-isolated filename fallback within storage_root and unique_roots
            case_folders_to_check = []
            if case_id:
                cid_str = str(case_id).strip()
                case_folders_to_check.append(cid_str)
                if cid_str.startswith("CASE-"):
                    case_folders_to_check.append(cid_str.replace("CASE-", ""))
                elif cid_str.startswith("case-"):
                    case_folders_to_check.append(cid_str.replace("case-", ""))
                else:
                    case_folders_to_check.append(f"CASE-{cid_str}")

            fname = direct.name
            unprefixed = None
            if len(fname) > 33 and fname[32] == "_" and all(c in "0123456789abcdefABCDEF" for c in fname[:32]):
                unprefixed = fname[33:]

            for root in unique_roots:
                for cid in case_folders_to_check:
                    cdir = (root / cid).resolve()
                    if not _is_safe(cdir) or not cdir.is_dir():
                        continue

                    # Exact name match
                    candidate = (cdir / fname).resolve()
                    if _is_safe(candidate) and candidate.is_file():
                        return candidate

                    # Unprefixed name match (if fname has UUID prefix)
                    if unprefixed:
                        candidate = (cdir / unprefixed).resolve()
                        if _is_safe(candidate) and candidate.is_file():
                            return candidate

                    # Match *_{target} or case-insensitive ending
                    target = unprefixed or fname
                    if target:
                        for f in cdir.glob(f"*_{target}"):
                            if _is_safe(f) and f.is_file():
                                return f.resolve()
                        target_lower = target.lower()
                        for f in cdir.iterdir():
                            if f.is_file():
                                f_lower = f.name.lower()
                                if f_lower == target_lower or f_lower.endswith(f"_{target_lower}"):
                                    if _is_safe(f):
                                        return f.resolve()

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
        raw_path = getattr(evidence, "file_path", None)
        file_name = getattr(evidence, "file_name", getattr(evidence, "original_filename", "evidence.bin"))

        resolved_path = cls.resolve_evidence_path(
            raw_path=raw_path,
            case_id=case_id,
            storage_key=storage_key
        )

        # Fallback with case.case_id if available
        if not resolved_path and case and hasattr(case, "case_id") and case.case_id:
            resolved_path = cls.resolve_evidence_path(
                raw_path=raw_path,
                case_id=case.case_id,
                storage_key=storage_key
            )

        # Fallback with file_name if raw_path did not resolve
        if not resolved_path and file_name:
            resolved_path = cls.resolve_evidence_path(
                raw_path=file_name,
                case_id=case_id,
                storage_key=storage_key
            )
            if not resolved_path and case and hasattr(case, "case_id") and case.case_id:
                resolved_path = cls.resolve_evidence_path(
                    raw_path=file_name,
                    case_id=case.case_id,
                    storage_key=storage_key
                )

        # Fallback with stored_filename if present
        stored_filename = getattr(evidence, "stored_filename", None)
        if not resolved_path and stored_filename:
            resolved_path = cls.resolve_evidence_path(
                raw_path=stored_filename,
                case_id=case_id,
                storage_key=storage_key
            )
            if not resolved_path and case and hasattr(case, "case_id") and case.case_id:
                resolved_path = cls.resolve_evidence_path(
                    raw_path=stored_filename,
                    case_id=case.case_id,
                    storage_key=storage_key
                )

        if not resolved_path or not resolved_path.is_file():
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Evidence file is not available in persistent storage."
            )

        mime_type = getattr(evidence, "mime_type", None)
        if not mime_type:
            mime_type, _ = mimetypes.guess_type(file_name)
        mime_type = mime_type or "application/octet-stream"

        return resolved_path, file_name, mime_type

