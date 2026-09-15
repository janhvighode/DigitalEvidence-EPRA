import os
import platform
import mimetypes
from pathlib import Path
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import func, or_
from PIL import Image

from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.user import User
from services.backend_adapter import get_backend_adapter, EvidenceItem, map_backend_verification_status

# Ensure decompression-bomb protection is active
Image.MAX_IMAGE_PIXELS = 89478485  # Pillow standard safe threshold (~89 megapixels)


def format_bytes(size_bytes: int) -> str:
    """Format bytes into readable units (B, KB, MB, GB, TB)."""
    if not size_bytes or size_bytes <= 0:
        return "0 B"
    units = ["B", "KB", "MB", "GB", "TB"]
    i = 0
    size = float(size_bytes)
    while size >= 1024.0 and i < len(units) - 1:
        size /= 1024.0
        i += 1
    if i == 0:
        return f"{int(size)} B"
    elif i == 1:
        return f"{size:.1f} KB" if size < 10 else f"{int(round(size))} KB"
    else:
        return f"{size:.1f} {units[i]}" if size < 100 else f"{int(round(size))} {units[i]}"


def classify_file_type_display(filename: str, mime_type: Optional[str] = None) -> Tuple[str, str]:
    """
    Return (category, display_label), e.g. ('IMAGE', 'JPEG Image'), ('PDF', 'PDF Document').
    """
    suffix = Path(filename).suffix.lower()
    if suffix in (".jpg", ".jpeg"):
        return "IMAGE", "JPEG Image"
    elif suffix == ".png":
        return "IMAGE", "PNG Image"
    elif suffix == ".gif":
        return "IMAGE", "GIF Image"
    elif suffix in (".bmp", ".tiff", ".webp"):
        return "IMAGE", f"{suffix[1:].upper()} Image"
    elif suffix == ".pdf":
        return "PDF", "PDF Document"
    elif suffix in (".mp4", ".mov", ".avi", ".mkv"):
        return "VIDEO", f"{suffix[1:].upper()} Video"
    elif suffix in (".mp3", ".wav", ".aac", ".flac", ".ogg"):
        return "AUDIO", f"{suffix[1:].upper()} Audio"
    elif suffix in (".xlsx", ".xls", ".csv"):
        return "SPREADSHEET", "Excel Document" if suffix != ".csv" else "CSV Spreadsheet"
    elif suffix in (".docx", ".doc"):
        return "DOCUMENT", "Word Document"
    elif suffix in (".txt", ".log", ".json", ".xml"):
        return "TEXT", f"{suffix[1:].upper()} Document"
    elif suffix in (".zip", ".tar", ".gz", ".7z", ".rar"):
        return "ARCHIVE", "Compressed Archive"
    return "OTHER", "Data File"


def _resolve_evidence_path(raw_path: Optional[str]) -> Optional[Path]:
    """Robust helper to locate stored evidence file on disk across environments."""
    if not raw_path:
        return None
    p = Path(raw_path)
    if p.is_file():
        return p.resolve()
    root = Path(__file__).resolve().parent.parent.parent
    backend = Path(__file__).resolve().parent.parent
    if (backend / p).is_file():
        return (backend / p).resolve()
    if (root / p).is_file():
        return (root / p).resolve()
    # Search under backend/uploads/ by filename if path came from container/Render
    fname = p.name
    uploads_dir = backend / "uploads"
    if uploads_dir.exists():
        matches = list(uploads_dir.glob(f"**/{fname}"))
        if matches:
            return matches[0].resolve()
    return p if p.exists() else None


class MetadataService:

    @staticmethod
    def persist_evidence_metadata(
        db: Session,
        case: Case,
        evidence: Evidence,
        evidence_hash: Optional[EvidenceHash] = None,
        current_user: Optional[User] = None
    ) -> EvidenceRecord:
        """
        Forensically extracts and persistently stores metadata for an evidence item into MySQL.
        Must be called on evidence upload and safe backfills.
        Idempotent and safe against destructive overwrites.
        """
        now_utc = datetime.now(timezone.utc)
        resolved_p = _resolve_evidence_path(evidence.file_path)
        has_file = resolved_p is not None and resolved_p.is_file()

        sys_os = platform.system()
        ctime_iso = None
        ctime_source = None
        mtime_iso = None
        mtime_source = None
        atime_iso = None
        atime_source = None
        file_size_bytes = evidence.file_size or 0

        if has_file:
            stat = resolved_p.stat()
            file_size_bytes = stat.st_size
            ctime_iso = datetime.fromtimestamp(stat.st_ctime, tz=timezone.utc)
            ctime_source = (
                "st_ctime (Windows: File Creation Time)"
                if sys_os == "Windows"
                else "st_ctime (POSIX: Inode Change Time - Not Creation Time)"
            )
            mtime_iso = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc)
            mtime_source = "st_mtime (Filesystem Last Modification Time)"
            atime_iso = datetime.fromtimestamp(stat.st_atime, tz=timezone.utc)
            atime_source = "st_atime (Filesystem Last Access Time)"

        cat, display_label = classify_file_type_display(evidence.file_name)
        guessed_mime, _ = mimetypes.guess_type(evidence.file_name)

        # Resolve SHA-256 and verification status
        sha256 = None
        v_status = "Unknown"
        v_time = None
        v_notes = None

        if evidence_hash:
            sha256 = evidence_hash.sha256_hash or evidence_hash.current_hash or evidence_hash.original_hash
            v_status = evidence_hash.integrity_status or ("Verified" if evidence_hash.hash_match else "Tampered")
            v_time = evidence_hash.verified_at
            v_notes = f"Integrity status: {v_status}"
        else:
            h_rec = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == evidence.id).first()
            if h_rec:
                sha256 = h_rec.sha256_hash or h_rec.current_hash or h_rec.original_hash
                v_status = h_rec.integrity_status or ("Verified" if h_rec.hash_match else "Tampered")
                v_time = h_rec.verified_at
                v_notes = f"Integrity status: {v_status}"

        # Query existing EvidenceRecord
        record = db.query(EvidenceRecord).filter(
            EvidenceRecord.external_evidence_id == str(evidence.evidence_id),
            or_(
                EvidenceRecord.case_id == str(case.case_id),
                EvidenceRecord.case_id == str(case.id)
            )
        ).first()

        if not record:
            record = EvidenceRecord(
                external_evidence_id=str(evidence.evidence_id),
                external_source="shared_backend",
                case_id=str(case.case_id),
                original_filename=evidence.file_name,
                stored_filename=Path(evidence.file_path).name if evidence.file_path else f"{evidence.evidence_id}_{evidence.file_name}",
                file_path=str(resolved_p or evidence.file_path).replace("\\", "/"),
                file_extension=Path(evidence.file_name).suffix.lower(),
                mime_type=guessed_mime or "application/octet-stream",
                mime_type_source="backend_supplied" if evidence.file_type else "extension_guessed",
                evidence_type=display_label,
                file_size_bytes=file_size_bytes,
                created_at=ctime_iso,
                created_at_source=ctime_source,
                modified_at=mtime_iso,
                modified_at_source=mtime_source,
                accessed_at=atime_iso,
                accessed_at_source=atime_source,
                uploaded_at=evidence.created_at or now_utc,
                original_sha256=sha256,
                current_sha256=sha256,
                verification_status=v_status,
                verification_timestamp=v_time,
                verification_source="Shared Backend Integrity Subsystem",
                verification_notes=v_notes,
                cached_at=now_utc,
                retrieved_at=now_utc,
                processing_status="SYNCHRONIZED"
            )
            db.add(record)
        else:
            # Safe update: never overwrite existing non-null fields with None
            record.original_filename = evidence.file_name
            record.file_path = str(resolved_p or evidence.file_path).replace("\\", "/")
            if file_size_bytes:
                record.file_size_bytes = file_size_bytes
            if ctime_iso:
                record.created_at = ctime_iso
                record.created_at_source = ctime_source
            if mtime_iso:
                record.modified_at = mtime_iso
                record.modified_at_source = mtime_source
            if atime_iso:
                record.accessed_at = atime_iso
                record.accessed_at_source = atime_source
            if evidence.created_at and not record.uploaded_at:
                record.uploaded_at = evidence.created_at
            if sha256:
                record.original_sha256 = sha256
                record.current_sha256 = sha256
            if v_status and v_status != "Unknown":
                record.verification_status = v_status
                record.verification_timestamp = v_time
                record.verification_notes = v_notes
            if guessed_mime:
                record.mime_type = guessed_mime
            record.evidence_type = display_label
            record.cached_at = now_utc

        return record

    @staticmethod
    def ensure_case_metadata_persisted(db: Session, case: Case):
        """
        Idempotently guarantees all Evidence rows for this case have an EvidenceRecord in MySQL.
        Zero writes/commits if all evidence items are already persisted.
        """
        evidences = db.query(Evidence).filter(Evidence.case_id == case.id).all()
        if not evidences:
            return

        existing = db.query(EvidenceRecord).filter(
            or_(
                EvidenceRecord.case_id == str(case.case_id),
                EvidenceRecord.case_id == str(case.id)
            )
        ).all()
        existing_ids = {r.external_evidence_id for r in existing if r.external_evidence_id}

        missing = [ev for ev in evidences if ev.evidence_id not in existing_ids]
        if missing:
            for ev in missing:
                h_rec = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
                MetadataService.persist_evidence_metadata(db, case, ev, h_rec)
            db.commit()

    @staticmethod
    def sync_case_from_adapter(db: Session, case_id: str):
        """
        Synchronize evidence items from the BackendAdapter into local EvidenceRecords.
        Explicitly tracks external_evidence_id and external_source.
        Only called on explicit extraction trigger.
        """
        adapter = get_backend_adapter()
        external_items = adapter.list_evidence(case_id)
        if not external_items:
            return

        now_utc = datetime.now(timezone.utc)
        for item in external_items:
            record = db.query(EvidenceRecord).filter(
                or_(
                    EvidenceRecord.case_id == case_id,
                    EvidenceRecord.case_id == str(item.case_id)
                ),
                EvidenceRecord.external_evidence_id == str(item.evidence_id)
            ).first()

            cat, display_label = classify_file_type_display(item.original_filename)

            item_mime = getattr(item, "mime_type", None)
            if item_mime:
                stored_mime = item_mime
                stored_mime_source = "backend_supplied"
            else:
                guessed, _ = mimetypes.guess_type(item.original_filename)
                if guessed:
                    stored_mime = guessed
                    stored_mime_source = "extension_guessed"
                else:
                    stored_mime = None
                    stored_mime_source = "unspecified"

            sha256 = item.original_sha256 or item.current_sha256

            if not record:
                record = EvidenceRecord(
                    external_evidence_id=str(item.evidence_id),
                    external_source=item.external_source or "shared_backend",
                    case_id=case_id,
                    original_filename=item.original_filename,
                    stored_filename=f"{item.evidence_id}_{item.original_filename}",
                    file_path=item.file_path or "",
                    file_extension=Path(item.original_filename).suffix.lower(),
                    mime_type=stored_mime,
                    mime_type_source=stored_mime_source,
                    evidence_type=display_label,
                    file_size_bytes=item.file_size_bytes,
                    created_at=item.created_at,
                    created_at_source=item.created_at_source,
                    modified_at=item.modified_at,
                    modified_at_source=item.modified_at_source,
                    accessed_at=item.accessed_at,
                    accessed_at_source=item.accessed_at_source,
                    uploaded_at=item.uploaded_at,
                    original_sha256=sha256,
                    current_sha256=item.current_sha256 or sha256,
                    verification_status=map_backend_verification_status(item.verification_status),
                    verification_timestamp=item.verification_timestamp,
                    verification_source=item.verification_source,
                    verification_notes=item.verification_notes,
                    cached_at=now_utc,
                    retrieved_at=now_utc,
                    processing_status="SYNCHRONIZED"
                )
                db.add(record)
            else:
                record.external_source = item.external_source or record.external_source
                record.original_filename = item.original_filename
                if item.file_path:
                    record.file_path = item.file_path
                if item.file_size_bytes:
                    record.file_size_bytes = item.file_size_bytes
                if item.uploaded_at:
                    record.uploaded_at = item.uploaded_at
                if item.created_at:
                    record.created_at = item.created_at
                    record.created_at_source = item.created_at_source or record.created_at_source
                if item.modified_at:
                    record.modified_at = item.modified_at
                    record.modified_at_source = item.modified_at_source or record.modified_at_source
                if item.accessed_at:
                    record.accessed_at = item.accessed_at
                    record.accessed_at_source = item.accessed_at_source or record.accessed_at_source
                if sha256:
                    record.original_sha256 = sha256
                    record.current_sha256 = sha256
                if item.verification_status:
                    record.verification_status = map_backend_verification_status(item.verification_status)
                if item.verification_timestamp:
                    record.verification_timestamp = item.verification_timestamp
                record.mime_type = stored_mime
                record.evidence_type = display_label
                record.cached_at = now_utc
                record.processing_status = "SYNCHRONIZED"

        db.commit()

    @staticmethod
    def get_case_summary(db: Session, case_id: str) -> Dict[str, Any]:
        """
        Summary cards scoped to the case:
        - Total Files
        - Total Size (bytes and formatted e.g. '1.42 GB')
        - File Types (count of distinct types)
        - Latest Upload timestamp
        - Hash verification metrics (verified, tampered, pending)
        Read-only query without modifying state.
        """
        ident_str = str(case_id).strip()
        case = db.query(Case).filter(
            or_(
                Case.id == int(ident_str) if ident_str.isdigit() else False,
                Case.case_id == ident_str,
                Case.case_id.ilike(ident_str)
            )
        ).first()

        if case:
            MetadataService.ensure_case_metadata_persisted(db, case)
            resolved_case_id = str(case.case_id)
            records = db.query(EvidenceRecord).filter(
                or_(
                    EvidenceRecord.case_id == str(case.case_id),
                    EvidenceRecord.case_id == str(case.id)
                )
            ).all()
        else:
            resolved_case_id = ident_str
            records = db.query(EvidenceRecord).filter(
                EvidenceRecord.case_id == ident_str
            ).all()

        if not records:
            return {
                "case_id": resolved_case_id,
                "total_files": 0,
                "total_size_bytes": 0,
                "total_size_formatted": "0 B",
                "distinct_file_types": 0,
                "latest_upload": None,
                "latest_upload_formatted": None,
                "hash_recorded_count": 0,
                "verified_files_count": 0,
                "tampered_files_count": 0,
                "pending_verification_count": 0
            }

        total_files = len(records)
        total_size_bytes = sum(r.file_size_bytes or 0 for r in records)

        distinct_types = set()
        latest_upload = None
        verified_count = 0
        tampered_count = 0
        pending_count = 0
        hash_count = 0

        for r in records:
            _, display = classify_file_type_display(r.original_filename, r.mime_type)
            distinct_types.add(display)

            if r.uploaded_at:
                if latest_upload is None or r.uploaded_at > latest_upload:
                    latest_upload = r.uploaded_at

            if r.original_sha256 or r.current_sha256:
                hash_count += 1
            if r.verification_status == "Verified":
                verified_count += 1
            elif r.verification_status == "Tampered":
                tampered_count += 1
            elif r.verification_status == "Pending":
                pending_count += 1

        return {
            "case_id": str(case.case_id),
            "total_files": total_files,
            "total_size_bytes": total_size_bytes,
            "total_size_formatted": format_bytes(total_size_bytes),
            "distinct_file_types": len(distinct_types),
            "latest_upload": latest_upload.isoformat() if latest_upload else None,
            "latest_upload_formatted": latest_upload.strftime("%d %b %Y, %H:%M") if latest_upload else None,
            "hash_recorded_count": hash_count,
            "verified_files_count": verified_count,
            "tampered_files_count": tampered_count,
            "pending_verification_count": pending_count
        }

    @staticmethod
    def get_metadata_table(
        db: Session,
        case_id: str,
        search: Optional[str] = None,
        sort_by: str = "id",
        sort_order: str = "asc",
        page: int = 1,
        page_size: int = 10
    ) -> Dict[str, Any]:
        """
        Searchable, paginated metadata table:
        Row numbers, evidence IDs, filenames, display labels, formatted sizes,
        provenance timestamps, and backend-supplied hash verification statuses.
        Strictly read-only: does not modify or delete metadata.
        """
        ident_str = str(case_id).strip()
        case = db.query(Case).filter(
            or_(
                Case.id == int(ident_str) if ident_str.isdigit() else False,
                Case.case_id == ident_str,
                Case.case_id.ilike(ident_str)
            )
        ).first()

        if case:
            MetadataService.ensure_case_metadata_persisted(db, case)
            resolved_case_id = str(case.case_id)
            query = db.query(EvidenceRecord).filter(
                or_(
                    EvidenceRecord.case_id == str(case.case_id),
                    EvidenceRecord.case_id == str(case.id)
                )
            )
        else:
            resolved_case_id = ident_str
            query = db.query(EvidenceRecord).filter(
                EvidenceRecord.case_id == ident_str
            )

        if search:
            s = f"%{search.strip().lower()}%"
            query = query.filter(
                func.lower(EvidenceRecord.original_filename).like(s) |
                func.lower(EvidenceRecord.external_evidence_id).like(s) |
                func.lower(EvidenceRecord.evidence_type).like(s)
            )

        # Sorting
        if sort_by == "filename":
            query = query.order_by(EvidenceRecord.original_filename.desc() if sort_order == "desc" else EvidenceRecord.original_filename.asc())
        elif sort_by == "size":
            query = query.order_by(EvidenceRecord.file_size_bytes.desc() if sort_order == "desc" else EvidenceRecord.file_size_bytes.asc())
        elif sort_by == "modified":
            query = query.order_by(EvidenceRecord.modified_at.desc() if sort_order == "desc" else EvidenceRecord.modified_at.asc())
        elif sort_by == "created":
            query = query.order_by(EvidenceRecord.created_at.desc() if sort_order == "desc" else EvidenceRecord.created_at.asc())
        else:
            query = query.order_by(EvidenceRecord.id.desc() if sort_order == "desc" else EvidenceRecord.id.asc())

        total = query.count()
        offset = (max(1, page) - 1) * page_size
        records = query.offset(offset).limit(page_size).all()

        items = []
        for idx, r in enumerate(records, start=offset + 1):
            ev_id = r.external_evidence_id or str(r.id)
            cat, display_label = classify_file_type_display(r.original_filename, r.mime_type)

            created_dt = r.created_at
            modified_dt = r.modified_at
            accessed_dt = r.accessed_at
            uploaded_dt = r.uploaded_at

            # Fallback formatting: if genuine timestamp exists, format it; else None
            created_formatted = created_dt.strftime("%d %b %Y, %H:%M:%S") if created_dt else (r.filesystem_ctime or None)
            modified_formatted = modified_dt.strftime("%d %b %Y, %H:%M:%S") if modified_dt else (r.filesystem_mtime or None)
            accessed_formatted = accessed_dt.strftime("%d %b %Y, %H:%M:%S") if accessed_dt else None
            uploaded_formatted = uploaded_dt.strftime("%d %b %Y, %H:%M:%S") if uploaded_dt else None

            # Resolve hash: ensure valid hash is never dropped
            sha256 = r.original_sha256 or r.current_sha256
            if not sha256:
                # Secondary lookup in evidence_hashes
                h_rec = (
                    db.query(EvidenceHash)
                    .join(Evidence, Evidence.id == EvidenceHash.evidence_id)
                    .filter(Evidence.evidence_id == ev_id)
                    .first()
                )
                if h_rec:
                    sha256 = h_rec.sha256_hash or h_rec.current_hash or h_rec.original_hash

            is_previewable = (cat == "IMAGE")

            items.append({
                "row_number": idx,
                "evidence_id": ev_id,
                "case_id": str(case.case_id),
                "filename": r.original_filename,
                "original_filename": r.original_filename,
                "file_type": r.evidence_type or display_label,
                "file_type_display": display_label,
                "file_category": cat,
                "file_size": format_bytes(r.file_size_bytes or 0),
                "file_size_bytes": r.file_size_bytes or 0,
                "size_bytes": r.file_size_bytes or 0,
                "size_formatted": format_bytes(r.file_size_bytes or 0),
                "created_at": created_dt.isoformat() if created_dt else None,
                "created_at_display": created_formatted,
                "created_at_source": r.created_at_source or r.filesystem_ctime_source,
                "modified_at": modified_dt.isoformat() if modified_dt else None,
                "modified_at_display": modified_formatted,
                "modified_at_source": r.modified_at_source or r.filesystem_mtime_source,
                "accessed_at": accessed_dt.isoformat() if accessed_dt else None,
                "accessed_at_display": accessed_formatted,
                "accessed_at_source": r.accessed_at_source,
                "uploaded_at": uploaded_dt.isoformat() if uploaded_dt else None,
                "uploaded_at_display": uploaded_formatted,
                "mime_type": r.mime_type,
                "file_extension": r.file_extension or Path(r.original_filename).suffix.lower(),
                "hash_status": r.verification_status or "Unknown",
                "sha256_hash": sha256,
                "has_preview": is_previewable,
                "preview_url": f"/cases/{case.case_id}/metadata/{ev_id}/preview" if is_previewable else None,
                "download_url": f"/cases/{case.case_id}/metadata/{ev_id}/download",
                "details_url": f"/cases/{case.case_id}/metadata/{ev_id}",
                "additional_metadata": {
                    "is_empty": r.is_empty_file,
                    "processing_status": r.processing_status
                }
            })

        total_pages = (total + page_size - 1) // page_size if page_size > 0 else 1

        return {
            "case_id": str(case.case_id),
            "total_items": total,
            "page": page,
            "page_size": page_size,
            "total_pages": total_pages,
            "items": items
        }

    @staticmethod
    def get_file_details(db: Session, evidence_id: str, case_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Selected-file details card matching approved UI and structured JSON response contract:
        - file_information
        - timestamp_information
        - integrity_information
        - additional_metadata
        Plus direct top-level fields and backward-compatible legacy sections.
        Strictly read-only: does not modify or re-save timestamps on disk access.
        """
        clean_ev_id = str(evidence_id).strip()
        parent_case = None
        if case_id:
            c_str = str(case_id).strip()
            parent_case = db.query(Case).filter(
                or_(
                    Case.id == int(c_str) if c_str.isdigit() else False,
                    Case.case_id == c_str,
                    Case.case_id.ilike(c_str)
                )
            ).first()

        # Look up in EvidenceRecord
        query = db.query(EvidenceRecord).filter(
            or_(
                EvidenceRecord.external_evidence_id == clean_ev_id,
                EvidenceRecord.id == int(clean_ev_id) if clean_ev_id.isdigit() else False
            )
        )
        if parent_case:
            query = query.filter(
                or_(
                    EvidenceRecord.case_id == str(parent_case.case_id),
                    EvidenceRecord.case_id == str(parent_case.id)
                )
            )
        record = query.first()

        # If not yet in EvidenceRecord, check core Evidence table and persist once
        if not record:
            ev_query = db.query(Evidence).filter(
                or_(
                    Evidence.evidence_id.ilike(clean_ev_id),
                    Evidence.id == int(clean_ev_id) if clean_ev_id.isdigit() else False
                )
            )
            if parent_case:
                ev_query = ev_query.filter(Evidence.case_id == parent_case.id)
            ev = ev_query.first()

            if ev:
                c = parent_case or db.query(Case).filter(Case.id == ev.case_id).first()
                if c:
                    h_rec = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
                    record = MetadataService.persist_evidence_metadata(db, c, ev, h_rec)
                    db.commit()

        if not record:
            # Fallback to adapter
            adapter = get_backend_adapter()
            ev_item = adapter.get_evidence(clean_ev_id, case_id=case_id)
            if not ev_item:
                raise FileNotFoundError(f"Evidence #{clean_ev_id} not found.")
            c = parent_case or (db.query(Case).filter(Case.case_id.ilike(ev_item.case_id)).first() if ev_item else None)
            if c:
                MetadataService.sync_case_from_adapter(db, str(c.case_id))
            else:
                MetadataService.sync_case_from_adapter(db, str(ev_item.case_id))
            record = db.query(EvidenceRecord).filter(
                EvidenceRecord.external_evidence_id == clean_ev_id,
                or_(
                    EvidenceRecord.case_id == str(case_id),
                    EvidenceRecord.case_id == str(c.case_id) if c else False,
                    EvidenceRecord.case_id == str(c.id) if c else False
                )
            ).first()
            if not record:
                raise FileNotFoundError(f"Evidence #{clean_ev_id} not found.")

        resolved_case_id = record.case_id
        cat, display_label = classify_file_type_display(record.original_filename, record.mime_type)

        if record.mime_type:
            final_mime = record.mime_type
            mime_source = record.mime_type_source or "backend_supplied"
        else:
            guessed, _ = mimetypes.guess_type(record.original_filename)
            final_mime = guessed or "application/octet-stream"
            mime_source = "extension_guessed" if guessed else "unspecified_fallback"

        file_size_formatted = f"{format_bytes(record.file_size_bytes)} ({record.file_size_bytes:,} bytes)"

        # Resolve SHA-256
        sha256 = record.original_sha256 or record.current_sha256
        if not sha256:
            h_rec = (
                db.query(EvidenceHash)
                .join(Evidence, Evidence.id == EvidenceHash.evidence_id)
                .filter(Evidence.evidence_id == (record.external_evidence_id or str(record.id)))
                .first()
            )
            if h_rec:
                sha256 = h_rec.sha256_hash or h_rec.current_hash or h_rec.original_hash

        # Image properties extraction via Pillow (read-only)
        is_image = (cat == "IMAGE")
        img_width = None
        img_height = None
        img_dimensions = None
        img_mode = None
        img_color_space = None
        img_note = None

        if is_image:
            resolved_p = _resolve_evidence_path(record.file_path)
            if resolved_p and resolved_p.is_file():
                try:
                    with open(resolved_p, "rb") as f_img:
                        with Image.open(f_img) as img:
                            img_width, img_height = img.size
                            img_dimensions = f"{img_width} x {img_height}"
                            img_mode = img.mode

                            icc = img.info.get("icc_profile")
                            if icc:
                                try:
                                    from io import BytesIO
                                    from PIL import ImageCms
                                    profile = ImageCms.getOpenProfile(BytesIO(icc))
                                    desc = ImageCms.getProfileDescription(profile)
                                    img_color_space = desc.strip() or f"Embedded ICC ({img.mode})"
                                except Exception:
                                    img_color_space = f"Embedded ICC Profile ({img.mode})"
                            else:
                                img_color_space = f"None embedded; Pixel Mode: {img.mode}"
                except Exception as e:
                    img_note = f"Image metadata extraction failed safely: {str(e)}"
            else:
                img_note = "File stream unavailable from disk; image dimensions not extracted"
        else:
            img_note = "Not applicable for non-image file"

        created_dt = record.created_at
        modified_dt = record.modified_at
        accessed_dt = record.accessed_at
        uploaded_dt = record.uploaded_at

        created_formatted = created_dt.strftime("%d %b %Y, %H:%M:%S") if created_dt else (record.filesystem_ctime or None)
        modified_formatted = modified_dt.strftime("%d %b %Y, %H:%M:%S") if modified_dt else (record.filesystem_mtime or None)
        accessed_formatted = accessed_dt.strftime("%d %b %Y, %H:%M:%S") if accessed_dt else None
        uploaded_formatted = uploaded_dt.strftime("%d %b %Y, %H:%M:%S") if uploaded_dt else None

        ev_id = record.external_evidence_id or str(record.id)

        # 1. Clean structured sections
        file_info = {
            "file_name": record.original_filename,
            "file_type": record.evidence_type or display_label,
            "file_category": cat,
            "mime_type": final_mime,
            "file_extension": record.file_extension or Path(record.original_filename).suffix.lower(),
            "file_size_bytes": record.file_size_bytes or 0,
            "file_size_display": format_bytes(record.file_size_bytes or 0)
        }

        timestamp_info = {
            "created_at": created_dt.isoformat() if created_dt else None,
            "created_at_display": created_formatted,
            "created_at_source": record.created_at_source or record.filesystem_ctime_source,
            "modified_at": modified_dt.isoformat() if modified_dt else None,
            "modified_at_display": modified_formatted,
            "modified_at_source": record.modified_at_source or record.filesystem_mtime_source,
            "accessed_at": accessed_dt.isoformat() if accessed_dt else None,
            "accessed_at_display": accessed_formatted,
            "accessed_at_source": record.accessed_at_source,
            "uploaded_at": uploaded_dt.isoformat() if uploaded_dt else None,
            "uploaded_at_display": uploaded_formatted
        }

        integrity_info = {
            "sha256_hash": sha256,
            "hash_status": record.verification_status or "Unknown",
            "verified_at": record.verification_timestamp.isoformat() if record.verification_timestamp else None,
            "verification_source": record.verification_source or "Shared Backend Integrity Subsystem",
            "verification_notes": record.verification_notes
        }

        additional_meta = {
            "dimensions": img_dimensions,
            "width": img_width,
            "height": img_height,
            "image_mode": img_mode,
            "color_space": img_color_space,
            "image_support_note": img_note,
            "is_empty": record.is_empty_file,
            "processing_status": record.processing_status
        }

        # Legacy models
        legacy_meta_info = {
            "file_name": record.original_filename,
            "file_type": record.evidence_type or display_label,
            "file_size": file_size_formatted,
            "created_at": created_dt.isoformat() if created_dt else None,
            "created_at_display": created_formatted or "N/A",
            "created_at_source": record.created_at_source or record.filesystem_ctime_source or "Filesystem ctime",
            "modified_at": modified_dt.isoformat() if modified_dt else None,
            "modified_at_display": modified_formatted or "N/A",
            "modified_at_source": record.modified_at_source or record.filesystem_mtime_source or "Filesystem mtime",
            "accessed_at": accessed_dt.isoformat() if accessed_dt else None,
            "accessed_at_display": accessed_formatted or "N/A",
            "accessed_at_source": record.accessed_at_source or "Application access event",
            "uploaded_at": uploaded_dt.isoformat() if uploaded_dt else None,
            "uploaded_at_display": uploaded_formatted or "N/A"
        }

        legacy_hash_info = {
            "sha256": sha256,
            "current_sha256": record.current_sha256 or sha256,
            "verification_status": record.verification_status or "Unknown",
            "verified_at": record.verification_timestamp.isoformat() if record.verification_timestamp else None,
            "verification_source": record.verification_source or "Shared Backend Integrity Subsystem",
            "verification_notes": record.verification_notes
        }

        legacy_props = {
            "extension": record.file_extension or Path(record.original_filename).suffix.lower(),
            "mime_type": final_mime,
            "mime_type_source": mime_source,
            "is_image": is_image,
            "dimensions": img_dimensions,
            "width": img_width,
            "height": img_height,
            "image_mode": img_mode,
            "color_space": img_color_space,
            "image_support_note": img_note
        }

        return {
            "evidence_id": ev_id,
            "case_id": resolved_case_id,

            # Clean structured sections
            "file_information": file_info,
            "timestamp_information": timestamp_info,
            "integrity_information": integrity_info,
            "additional_metadata": additional_meta,

            # Direct top-level summary fields
            "filename": record.original_filename,
            "file_type": record.evidence_type or display_label,
            "file_type_display": display_label,
            "file_category": cat,
            "file_size": file_size_formatted,
            "file_size_bytes": record.file_size_bytes or 0,
            "created_at": created_dt.isoformat() if created_dt else None,
            "created_at_display": created_formatted,
            "created_at_source": record.created_at_source or record.filesystem_ctime_source,
            "modified_at": modified_dt.isoformat() if modified_dt else None,
            "modified_at_display": modified_formatted,
            "modified_at_source": record.modified_at_source or record.filesystem_mtime_source,
            "accessed_at": accessed_dt.isoformat() if accessed_dt else None,
            "accessed_at_display": accessed_formatted,
            "accessed_at_source": record.accessed_at_source,
            "uploaded_at": uploaded_dt.isoformat() if uploaded_dt else None,
            "uploaded_at_display": uploaded_formatted,
            "mime_type": final_mime,
            "file_extension": record.file_extension or Path(record.original_filename).suffix.lower(),
            "sha256_hash": sha256,
            "hash_status": record.verification_status or "Unknown",

            # Legacy blocks preserved for 100% backward compatibility
            "metadata_information": legacy_meta_info,
            "hash_information": legacy_hash_info,
            "file_properties": legacy_props,
            "download_url": f"/cases/{resolved_case_id}/metadata/{ev_id}/download",
            "preview_url": f"/cases/{resolved_case_id}/metadata/{ev_id}/preview" if is_image else None
        }

    @staticmethod
    def extract_metadata(file_path: str) -> dict:
        """
        Standalone technical metadata extraction for a file path.
        Distinguishes filesystem timestamps from original evidence creation.
        """
        path = Path(file_path)
        if not path.exists():
            raise FileNotFoundError(f"File not found: {file_path}")
        if not path.is_file():
            raise ValueError(f"Path is not a file: {file_path}")

        stat = path.stat()
        mime_type, _ = mimetypes.guess_type(path.name)
        sys_os = platform.system()
        ctime_source = (
            "st_ctime (Windows: File Creation Time)"
            if sys_os == "Windows"
            else "st_ctime (POSIX: Inode Change Time - Not Creation Time)"
        )
        mtime_source = "st_mtime (Filesystem Last Modification Time)"

        ctime_iso = datetime.fromtimestamp(stat.st_ctime, tz=timezone.utc).isoformat()
        mtime_iso = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat()

        cat, display = classify_file_type_display(path.name, mime_type)

        res = {
            "file_name": path.name,
            "file_extension": path.suffix.lower(),
            "file_size_bytes": stat.st_size,
            "file_size_formatted": format_bytes(stat.st_size),
            "file_type_display": display,
            "mime_type": mime_type or "application/octet-stream",
            "filesystem_ctime": ctime_iso,
            "filesystem_ctime_source": ctime_source,
            "filesystem_mtime": mtime_iso,
            "filesystem_mtime_source": mtime_source,
            "created_at": ctime_iso,
            "modified_at": mtime_iso,
            "is_empty": (stat.st_size == 0),
            "extracted_at": datetime.now(timezone.utc).isoformat()
        }

        if cat == "IMAGE":
            try:
                with Image.open(path) as img:
                    res["width"], res["height"] = img.size
                    res["dimensions"] = f"{img.size[0]} x {img.size[1]}"
                    res["image_mode"] = img.mode
            except Exception:
                pass

        return res
