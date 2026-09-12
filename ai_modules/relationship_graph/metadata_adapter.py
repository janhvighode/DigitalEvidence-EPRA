# ============================================================
# Digital Evidence EPRA
# Module : Relationship Graph / Metadata Integration
# File   : metadata_adapter.py
# Purpose: Thin adapter delegating to the shared project MetadataService
#          and EvidenceClassifier to enrich the Relationship Graph.
# ============================================================

import os
import sys
from pathlib import Path
from datetime import datetime, timezone

# Ensure project root and backend are in sys.path
CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
BACKEND_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "backend"))
BACKEND_APP_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "backend", "app"))
BACKEND_SERVICES_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "backend", "services"))

for p in [PROJECT_ROOT, BACKEND_DIR, BACKEND_APP_DIR, BACKEND_SERVICES_DIR]:
    if p not in sys.path:
        sys.path.insert(0, p)

# Shared team metadata service (from backend/services or backend/app/services)
try:
    from backend.services.metadata_service import MetadataService, classify_file_type_display, format_bytes
except ImportError:
    try:
        from services.metadata_service import MetadataService, classify_file_type_display, format_bytes
    except ImportError:
        try:
            from backend.app.services.metadata_service import MetadataService, classify_file_type_display, format_bytes
        except ImportError:
            MetadataService = None
            classify_file_type_display = None
            format_bytes = None

# Shared evidence classifier
try:
    from backend.services.evidence_classifier import EvidenceClassifier
except ImportError:
    try:
        from services.evidence_classifier import EvidenceClassifier
    except ImportError:
        EvidenceClassifier = None


class MetadataAdapter:
    """
    Thin adapter that reuses the team's shared MetadataService and EvidenceClassifier
    to provide verified metadata for Relationship Graph nodes and details.
    """

    @staticmethod
    def extract_file_metadata(file_path: str, fallback_info: dict = None) -> dict:
        """
        Extract technical file metadata by delegating directly to shared MetadataService.
        Never fabricates fictional metadata if the file is missing or unreadable.
        """
        fallback = fallback_info or {}
        if not file_path:
            return MetadataAdapter._build_fallback_metadata(fallback, "No file path provided")

        p = Path(file_path)
        if not p.exists() or not p.is_file():
            return MetadataAdapter._build_fallback_metadata(fallback, f"File not found on disk: {p.name}")

        # Delegate directly to shared MetadataService if available
        if MetadataService is not None and hasattr(MetadataService, "extract_metadata"):
            try:
                extracted = MetadataService.extract_metadata(str(p))
                return {
                    "file_name": extracted.get("file_name", p.name),
                    "filename": extracted.get("file_name", p.name),
                    "file_extension": extracted.get("file_extension", p.suffix.lower()),
                    "file_size_bytes": extracted.get("file_size_bytes", 0),
                    "file_size_formatted": extracted.get("file_size_formatted", "0 B"),
                    "file_type_display": extracted.get("file_type_display", "Data File"),
                    "mime_type": extracted.get("mime_type", "application/octet-stream"),
                    "created_at": extracted.get("created_at"),
                    "modified_at": extracted.get("modified_at"),
                    "filesystem_ctime": extracted.get("filesystem_ctime"),
                    "filesystem_mtime": extracted.get("filesystem_mtime"),
                    "dimensions": extracted.get("dimensions"),
                    "width": extracted.get("width"),
                    "height": extracted.get("height"),
                    "image_mode": extracted.get("image_mode"),
                    "provenance": "Shared MetadataService (extract_metadata)",
                    "status": "Verified Technical Metadata"
                }
            except Exception as e:
                return MetadataAdapter._build_fallback_metadata(
                    fallback, f"Shared MetadataService extraction failed safely: {str(e)}"
                )

        # Fallback: classify using shared EvidenceClassifier if available
        file_type = "Data File"
        mime_type = "application/octet-stream"
        if EvidenceClassifier is not None:
            try:
                cl = EvidenceClassifier.classify(str(p))
                file_type = cl.get("evidence_type", "Data File")
                mime_type = cl.get("mime_type", "application/octet-stream")
            except Exception:
                pass

        try:
            stat = p.stat()
            size_b = stat.st_size
            sz_fmt = f"{size_b} B" if size_b < 1024 else f"{size_b / 1024:.1f} KB"
            c_iso = datetime.fromtimestamp(stat.st_ctime, tz=timezone.utc).isoformat()
            m_iso = datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat()
            return {
                "file_name": p.name,
                "filename": p.name,
                "file_extension": p.suffix.lower(),
                "file_size_bytes": size_b,
                "file_size_formatted": sz_fmt,
                "file_type_display": file_type,
                "mime_type": mime_type,
                "created_at": c_iso,
                "modified_at": m_iso,
                "dimensions": None,
                "provenance": "Shared EvidenceClassifier + Standard Stat",
                "status": "Verified Technical Metadata"
            }
        except Exception as e:
            return MetadataAdapter._build_fallback_metadata(fallback, f"Metadata extraction failed: {str(e)}")

    @staticmethod
    def _build_fallback_metadata(fallback: dict, reason: str) -> dict:
        fn = fallback.get("filename") or fallback.get("file_name") or fallback.get("evidence_id", "Unknown")
        cat = fallback.get("category") or fallback.get("evidence_type") or "Evidence"
        return {
            "file_name": fn,
            "filename": fn,
            "file_extension": Path(fn).suffix.lower() if fn else "",
            "file_size_bytes": fallback.get("file_size_bytes", 0),
            "file_size_formatted": fallback.get("file_size_formatted", "Not Available"),
            "file_type_display": cat,
            "mime_type": fallback.get("mime_type", "Not Available"),
            "created_at": fallback.get("created_at"),
            "modified_at": fallback.get("modified_at"),
            "dimensions": fallback.get("dimensions"),
            "provenance": "Case Database Record",
            "status": f"Database Fallback ({reason})"
        }

    @staticmethod
    def build_clean_node_details(node_id: str, node_data: dict) -> dict:
        """
        Build a clean, investigator-friendly Node Details structure.
        Strictly excludes raw SHA-256 hexadecimal digests and internal absolute filesystem paths.
        Unavailable optional fields are marked 'Not Available' or cleanly omitted.
        """
        data = node_data or {}
        n_type = str(data.get("type", "Entity"))
        lbl = data.get("label", str(node_id))
        meta = data.get("metadata") or {}

        # 1. Case Root Node Details
        if n_type.lower() == "case" or n_type.lower().startswith("case:"):
            return {
                "entity_category": "Case",
                "case_id": str(node_id),
                "case_name": lbl
            }

        # 2. Person / Suspect Node Details (Only standalone person entities, NOT evidence photos)
        if (
            "evidence" not in n_type.lower()
            and ("person" in n_type.lower() or "suspect" in n_type.lower())
        ):
            return {
                "entity_category": "Person / Suspect",
                "person_id": str(node_id),
                "name": lbl,
                "role": "Person of Interest / Suspect",
                "case_id": data.get("case_id", "Not Available")
            }

        # 3. Device Node Details (Only standalone hardware devices)
        if (
            "evidence" not in n_type.lower()
            and any(k in n_type.lower() for k in ["device", "mobile", "computer", "laptop", "phone"])
        ):
            user = data.get("owner") or data.get("suspect") or data.get("user")
            return {
                "entity_category": "Device",
                "device_id": str(node_id),
                "device_type": n_type,
                "device_name": lbl,
                "user_or_owner": user if user else "Not Available",
                "case_id": data.get("case_id", "Not Available")
            }

        # 4. Evidence Node Details (All evidence types: Image, PDF, Document, Audio, Video, etc.)
        img_p = data.get("image_path") or data.get("file_path") or ""
        fn = os.path.basename(img_p) if img_p else meta.get("file_name", data.get("filename", lbl))

        sz = meta.get("file_size_formatted") or data.get("file_size_formatted") or "Not Available"
        ft = meta.get("file_type_display") or data.get("file_type") or n_type
        c_at = meta.get("created_at") or data.get("created_at") or "Not Available"
        m_at = meta.get("modified_at") or data.get("modified_at") or "Not Available"
        acq = data.get("acquisition_time") or meta.get("acquisition_time") or "Not Available"
        src = data.get("source") or meta.get("source") or "Case Evidence Registry"
        src_dev = data.get("source_device") or data.get("device") or "Not Available"
        desc = data.get("description") or "Not Available"
        mime = meta.get("mime_type") or "Not Available"
        dims = meta.get("dimensions")

        details = {
            "entity_category": "Evidence",
            "evidence_id": str(node_id),
            "evidence_type": n_type,
            "filename": fn,
            "description": desc,
            "file_size": sz,
            "file_type": ft,
            "mime_type": mime,
            "created": c_at,
            "modified": m_at,
            "acquisition_time": acq,
            "source": src,
            "source_device": src_dev,
            "metadata_provenance": meta.get("provenance", "Case Database Record")
        }

        if dims:
            details["dimensions"] = dims

        # If duplicate status has been verified via shared SHA-256, report it meaningfully
        if data.get("is_exact_duplicate") or data.get("sha256_exact_duplicate"):
            details["duplicate_status"] = "EXACT DUPLICATE — VERIFIED"

        return details
