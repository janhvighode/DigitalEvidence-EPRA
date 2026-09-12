import os
import platform
import mimetypes
from pathlib import Path
from datetime import datetime, timezone
from typing import Optional, Dict, Any, List, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import func
from PIL import Image

from models.evidence_record import EvidenceRecord
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


class MetadataService:

    @staticmethod
    def sync_case_from_adapter(db: Session, case_id: str):
        """
        Synchronize evidence items from the BackendAdapter into local EvidenceRecords.
        Explicitly tracks external_evidence_id and external_source.
        """
        adapter = get_backend_adapter()
        external_items = adapter.list_evidence(case_id)
        if not external_items:
            return

        now_utc = datetime.now(timezone.utc)
        for item in external_items:
            # Check if already present by external_evidence_id
            record = db.query(EvidenceRecord).filter(
                EvidenceRecord.case_id == case_id,
                EvidenceRecord.external_evidence_id == str(item.evidence_id)
            ).first()

            cat, display_label = classify_file_type_display(item.original_filename)

            # Determine MIME type and provenance without mislabeling fallback as detected
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

            if not record:
                # Insert synchronized record. Never substitute current time for missing uploaded_at
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
                    uploaded_at=item.uploaded_at,  # Missing remains None
                    original_sha256=item.original_sha256,
                    current_sha256=item.current_sha256,
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
                # Explicit cache refresh: do not mask withdrawn or updated source values with stale local values
                record.external_source = item.external_source or record.external_source
                record.original_filename = item.original_filename
                record.file_path = item.file_path or record.file_path
                record.file_size_bytes = item.file_size_bytes
                record.uploaded_at = item.uploaded_at  # Explicit refresh from source
                record.created_at = item.created_at or record.created_at
                record.created_at_source = item.created_at_source or record.created_at_source
                record.modified_at = item.modified_at or record.modified_at
                record.modified_at_source = item.modified_at_source or record.modified_at_source
                record.accessed_at = item.accessed_at or record.accessed_at
                record.accessed_at_source = item.accessed_at_source or record.accessed_at_source
                record.original_sha256 = item.original_sha256
                record.current_sha256 = item.current_sha256
                record.verification_status = map_backend_verification_status(item.verification_status)
                record.verification_timestamp = item.verification_timestamp
                record.verification_source = item.verification_source
                record.verification_notes = item.verification_notes
                record.mime_type = stored_mime
                record.mime_type_source = stored_mime_source
                record.evidence_type = display_label
                record.cached_at = now_utc
                record.retrieved_at = now_utc
                record.processing_status = "SYNCHRONIZED"

        db.commit()

    @staticmethod
    def get_case_summary(db: Session, case_id: str) -> Dict[str, Any]:
        """
        Summary cards scoped to the case matching Screenshot 1:
        - Total Files
        - Total Size (bytes and formatted e.g. '1.42 GB')
        - File Types (count of distinct types)
        - Latest Upload timestamp
        For empty cases, returns zero counts and null latest upload.
        """
        MetadataService.sync_case_from_adapter(db, case_id)

        records = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == case_id).all()
        if not records:
            return {
                "case_id": case_id,
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

            if r.original_sha256:
                hash_count += 1
            if r.verification_status == "Verified":
                verified_count += 1
            elif r.verification_status == "Tampered":
                tampered_count += 1
            elif r.verification_status == "Pending":
                pending_count += 1

        return {
            "case_id": case_id,
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
        Searchable, paginated metadata table matching Screenshot 1:
        - Row number (1-based across pages)
        - Evidence ID
        - Original filename
        - File type display label
        - Size (formatted and bytes)
        - Created At timestamp & source
        - Modified At timestamp & source
        - Hash Status (backend verification status: Verified, Tampered, Unknown, Pending, Error)
        - Actions (view details, preview URL, download URL)
        """
        MetadataService.sync_case_from_adapter(db, case_id)

        query = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == case_id)

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

            created_formatted = created_dt.strftime("%d %b %Y\n%H:%M") if created_dt else (r.filesystem_ctime or "N/A")
            modified_formatted = modified_dt.strftime("%d %b %Y\n%H:%M") if modified_dt else (r.filesystem_mtime or "N/A")

            # Determine preview support
            is_previewable = cat == "IMAGE"

            items.append({
                "row_number": idx,
                "evidence_id": ev_id,
                "original_filename": r.original_filename,
                "file_type": r.evidence_type or display_label,
                "file_type_display": display_label,
                "file_category": cat,
                "size_bytes": r.file_size_bytes or 0,
                "size_formatted": format_bytes(r.file_size_bytes or 0),
                "created_at": created_dt.isoformat() if created_dt else None,
                "created_at_display": created_formatted,
                "created_at_source": r.created_at_source or r.filesystem_ctime_source or "Filesystem ctime",
                "modified_at": modified_dt.isoformat() if modified_dt else None,
                "modified_at_display": modified_formatted,
                "modified_at_source": r.modified_at_source or r.filesystem_mtime_source or "Filesystem mtime",
                "hash_status": r.verification_status or "Unknown",
                "sha256_hash": r.original_sha256,
                "has_preview": is_previewable,
                "preview_url": f"/cases/{case_id}/metadata/{ev_id}/preview" if is_previewable else None,
                "download_url": f"/cases/{case_id}/metadata/{ev_id}/download",
                "details_url": f"/cases/{case_id}/metadata/{ev_id}"
            })

        total_pages = (total + page_size - 1) // page_size if page_size > 0 else 1

        return {
            "case_id": case_id,
            "total_items": total,
            "page": page,
            "page_size": page_size,
            "total_pages": total_pages,
            "items": items
        }

    @staticmethod
    def get_file_details(db: Session, evidence_id: str, case_id: Optional[str] = None) -> Dict[str, Any]:
        """
        Selected-file details card matching Screenshot 1 right panel.
        Extracts genuine image properties (dimensions, mode, color profile) via Pillow safely.
        Never exposes internal file_path in public schemas.
        """
        clean_ev_id = str(evidence_id).strip()

        query = db.query(EvidenceRecord).filter(
            (EvidenceRecord.external_evidence_id == clean_ev_id) |
            (EvidenceRecord.id == clean_ev_id if clean_ev_id.isdigit() else False)
        )
        if case_id:
            query = query.filter(EvidenceRecord.case_id == str(case_id))
        record = query.first()

        # If not in local DB, check adapter
        if not record:
            adapter = get_backend_adapter()
            ev_item = adapter.get_evidence(clean_ev_id, case_id=case_id)
            if not ev_item:
                raise FileNotFoundError(f"Evidence #{clean_ev_id} not found.")
            # Sync to local DB
            MetadataService.sync_case_from_adapter(db, ev_item.case_id)
            query2 = db.query(EvidenceRecord).filter(
                EvidenceRecord.external_evidence_id == clean_ev_id
            )
            if case_id:
                query2 = query2.filter(EvidenceRecord.case_id == str(case_id))
            record = query2.first()
            if not record:
                raise FileNotFoundError(f"Evidence #{clean_ev_id} not found.")

        cat, display_label = classify_file_type_display(record.original_filename, record.mime_type)
        if record.mime_type:
            final_mime = record.mime_type
            mime_source = record.mime_type_source or "backend_supplied"
        else:
            guessed, _ = mimetypes.guess_type(record.original_filename)
            if guessed:
                final_mime = guessed
                mime_source = "extension_guessed"
            else:
                final_mime = "application/octet-stream"
                mime_source = "unspecified_fallback"

        file_size_formatted = f"{format_bytes(record.file_size_bytes)} ({record.file_size_bytes:,} bytes)"

        # Image properties extraction via Pillow
        is_image = (cat == "IMAGE")
        img_width = None
        img_height = None
        img_dimensions = None
        img_mode = None
        img_color_space = None
        img_note = None

        if is_image:
            stream_obj = None
            should_close = False
            if record.file_path and Path(record.file_path).exists():
                try:
                    stream_obj = open(record.file_path, "rb")
                    should_close = True
                except Exception:
                    stream_obj = None

            if not stream_obj:
                adapter = get_backend_adapter()
                stream_tuple = adapter.get_evidence_file_stream(clean_ev_id)
                if stream_tuple:
                    stream_obj = stream_tuple[0]
                    should_close = True

            if stream_obj:
                try:
                    # Open with Pillow using decompression bomb protection
                    with Image.open(stream_obj) as img:
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
                finally:
                    if should_close:
                        try:
                            stream_obj.close()
                        except Exception:
                            pass
            else:
                img_note = "File stream unavailable from backend; image dimensions not extracted"
        else:
            img_note = "Not applicable for non-image file"

        c_id = record.case_id
        return {
            "evidence_id": record.external_evidence_id or str(record.id),
            "case_id": c_id,
            "filename": record.original_filename,
            "file_type": record.evidence_type or display_label,
            "file_type_display": display_label,
            "file_category": cat,
            "file_size": file_size_formatted,
            "file_size_bytes": record.file_size_bytes,
            "metadata_information": {
                "file_name": record.original_filename,
                "file_type": record.evidence_type or display_label,
                "file_size": file_size_formatted,
                "created_at": record.created_at.isoformat() if record.created_at else None,
                "created_at_display": record.created_at.strftime("%d %b %Y, %H:%M:%S") if record.created_at else "N/A",
                "created_at_source": record.created_at_source or record.filesystem_ctime_source or "Filesystem ctime",
                "modified_at": record.modified_at.isoformat() if record.modified_at else None,
                "modified_at_display": record.modified_at.strftime("%d %b %Y, %H:%M:%S") if record.modified_at else "N/A",
                "modified_at_source": record.modified_at_source or record.filesystem_mtime_source or "Filesystem mtime",
                "accessed_at": record.accessed_at.isoformat() if record.accessed_at else None,
                "accessed_at_display": record.accessed_at.strftime("%d %b %Y, %H:%M:%S") if record.accessed_at else "N/A",
                "accessed_at_source": record.accessed_at_source or "Application access event",
                "uploaded_at": record.uploaded_at.isoformat() if record.uploaded_at else None,
                "uploaded_at_display": record.uploaded_at.strftime("%d %b %Y, %H:%M:%S") if record.uploaded_at else "N/A"
            },
            "hash_information": {
                "sha256": record.original_sha256 or "Pending generation by backend",
                "current_sha256": record.current_sha256,
                "verification_status": record.verification_status or "Unknown",
                "verified_at": record.verification_timestamp.isoformat() if record.verification_timestamp else None,
                "verification_source": record.verification_source or "Shared Backend Integrity Subsystem",
                "verification_notes": record.verification_notes
            },
            "file_properties": {
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
            },
            "download_url": f"/cases/{c_id}/metadata/{record.external_evidence_id or record.id}/download",
            "preview_url": f"/cases/{c_id}/metadata/{record.external_evidence_id or record.id}/preview" if is_image else None
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
        ctime_source = "st_ctime (Windows: File Creation Time)" if sys_os == "Windows" else "st_ctime (POSIX: Inode Change Time - Not Creation Time)"
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

        # If image, extract dimensions
        if cat == "IMAGE":
            try:
                with Image.open(path) as img:
                    res["width"], res["height"] = img.size
                    res["dimensions"] = f"{img.size[0]} x {img.size[1]}"
                    res["image_mode"] = img.mode
            except Exception:
                pass

        return res
