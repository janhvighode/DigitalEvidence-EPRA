from datetime import datetime, timezone
from typing import Dict, Any, List, Optional
from sqlalchemy.orm import Session

from app.models.evidence_record import EvidenceRecord
from app.models.custody_log import CustodyLog
from app.services.backend_adapter import get_backend_adapter, map_backend_verification_status
from app.services.metadata_service import MetadataService, classify_file_type_display


class DownstreamService:

    @staticmethod
    def get_epra_payload(db: Session, case_id: str) -> Dict[str, Any]:
        """
        Construct structured data contract from Member 5 for EPRA module consumption.
        Exposes case and evidence references, technical metadata, backend-supplied hashes,
        verification statuses, and factual custody trails.
        Never exposes internal file_path directly; uses controlled access URLs.
        Preserves measured/pending status and provenance.
        """
        clean_case_id = case_id.strip()
        now_utc = datetime.now(timezone.utc).isoformat()

        MetadataService.sync_case_from_adapter(db, clean_case_id)
        adapter = get_backend_adapter()

        # Query all evidence records for the case
        evidence_items = db.query(EvidenceRecord).filter(
            EvidenceRecord.case_id == clean_case_id
        ).order_by(EvidenceRecord.id.asc()).all()

        evidence_payload_list = []
        type_counts = {}
        status_counts = {
            "Verified": 0,
            "Tampered": 0,
            "Pending": 0,
            "Unknown": 0,
            "Error": 0
        }

        for ev in evidence_items:
            ev_id = ev.external_evidence_id or str(ev.id)
            cat, display = classify_file_type_display(ev.original_filename, ev.mime_type)

            verification_status = map_backend_verification_status(ev.verification_status)
            if verification_status in status_counts:
                status_counts[verification_status] += 1
            else:
                status_counts["Unknown"] += 1

            type_counts[display] = type_counts.get(display, 0) + 1

            # Custody history count
            custody_count = db.query(CustodyLog).filter(
                (CustodyLog.evidence_id == ev_id) | (CustodyLog.evidence_id == str(ev.id))
            ).count()

            recent_custody = db.query(CustodyLog).filter(
                (CustodyLog.evidence_id == ev_id) | (CustodyLog.evidence_id == str(ev.id))
            ).order_by(CustodyLog.timestamp.desc()).first()

            evidence_payload_list.append({
                "evidence_id": ev_id,
                "case_id": ev.case_id,
                "original_filename": ev.original_filename,
                "file_type": ev.evidence_type or display,
                "mime_type": ev.mime_type,
                "file_size_bytes": ev.file_size_bytes or 0,
                "upload_timestamp": ev.uploaded_at.isoformat() if ev.uploaded_at else None,
                "baseline_hash": ev.original_sha256,
                "latest_current_hash": ev.current_sha256,
                "integrity_status": verification_status,
                "latest_verification_timestamp": ev.verification_timestamp.isoformat() if ev.verification_timestamp else None,
                "custody_events_count": custody_count,
                "recent_custody_action": recent_custody.action if recent_custody else None,
                "download_url": f"/evidence/{ev_id}/download",
                "preview_url": f"/evidence/{ev_id}/preview" if cat == "IMAGE" else None,
                "metadata": {
                    "extension": ev.file_extension,
                    "filesystem_ctime": ev.filesystem_ctime,
                    "filesystem_ctime_source": ev.filesystem_ctime_source,
                    "filesystem_mtime": ev.filesystem_mtime,
                    "filesystem_mtime_source": ev.filesystem_mtime_source,
                    "is_empty_file": ev.is_empty_file or False,
                    "processing_status": ev.processing_status
                }
            })

        # All case custody events
        all_custody = db.query(CustodyLog).filter(
            CustodyLog.case_id == clean_case_id
        ).order_by(CustodyLog.timestamp.asc(), CustodyLog.id.asc()).all()

        custody_trail = [
            {
                "id": c.id,
                "external_event_id": c.external_event_id,
                "evidence_id": c.evidence_id,
                "event_type": c.event_type,
                "title": c.title,
                "action": c.action,
                "actor": c.investigator_name,
                "actor_role": c.actor_role,
                "result": c.result,
                "timestamp": c.timestamp.isoformat() if c.timestamp else None,
                "remarks": c.remarks
            }
            for c in all_custody
        ]

        # Suspects from adapter
        suspect_items = adapter.get_suspects(clean_case_id)
        suspect_list = [s.model_dump() for s in suspect_items]
        suspect_avail = "AVAILABLE" if suspect_list else "NO_SUSPECT_INFORMATION_AVAILABLE"

        # EPRA analysis from adapter
        epra_items = adapter.get_epra_analysis(clean_case_id)
        epra_list = [e.model_dump() for e in epra_items]
        epra_avail = "AVAILABLE" if epra_list else "EPRA_INTEGRATION_PENDING"

        return {
            "contract_version": "2.0.0",
            "source_module": "Member 5 Metadata, Custody & Reporting",
            "target_consumer": "Proposed Contract for EPRA Prioritization & Analysis Module",
            "case_id": clean_case_id,
            "generated_at": now_utc,
            "total_evidence_count": len(evidence_payload_list),
            "evidence_summary": {
                "type_breakdown": type_counts,
                "integrity_breakdown": status_counts
            },
            "suspect_availability": suspect_avail,
            "suspect_count": len(suspect_list),
            "suspect_records": suspect_list,
            "epra_analysis_availability": epra_avail,
            "epra_analysis_records": epra_list,
            "evidence_records": evidence_payload_list,
            "custody_trail": custody_trail,
            "integration_notes": {
                "contract_status": "Proposed downstream schema; end-to-end EPRA prioritization and scoring mapping is pending.",
                "hash_standard": "SHA-256 (64 hex characters) - supplied by external backend",
                "integrity_outcomes": "Verified (Unchanged), Tampered (Modified), Pending, Unknown, Error",
                "database_integration_status": "Standalone SQLite verified; shared backend connection pending."
            }
        }
