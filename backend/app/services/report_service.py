import json
from uuid import uuid4
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Any, List
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.schemas.report_schema import ReportRequest, ReportType, DEFAULT_SECTIONS_BY_TYPE, ALL_REPORT_SECTIONS
from app.models.report_record import ReportRecord
from app.models.evidence_record import EvidenceRecord
from app.models.custody_log import CustodyLog
from app.models.activity_log import ActivityLog
from app.services.backend_adapter import get_backend_adapter, map_backend_verification_status
from app.services.metadata_service import MetadataService, format_bytes, classify_file_type_display
from app.services.custody_service import CustodyService
from app.services.timeline_service import TimelineService
from app.services.pdf_service import PDFService
from app.database import REPORTS_DIR, MANIFEST_DIR


class ReportService:

    @staticmethod
    def get_case_reporting_summary(db: Session, case_id: str) -> Dict[str, Any]:
        """
        Case summary cards matching Section 8:
        - Total Evidence
        - Verified Evidence (backend outcome 'Verified' / 'MATCH')
        - Changed / Possible Tampering (backend outcome 'Tampered' / 'MISMATCH')
        - Pending Verification (backend outcome 'Pending')
        - Unknown / Error / Missing Verification
        Hash availability alone does NOT count as verified!
        """
        MetadataService.sync_case_from_adapter(db, case_id)

        records = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == case_id).all()
        total = len(records)
        verified = 0
        tampered = 0
        pending = 0
        unknown = 0

        for r in records:
            status = map_backend_verification_status(r.verification_status)
            if status == "Verified":
                verified += 1
            elif status == "Tampered":
                tampered += 1
            elif status == "Pending":
                pending += 1
            else:
                unknown += 1

        return {
            "case_id": case_id,
            "total_evidence": total,
            "verified_evidence": verified,
            "tampered_evidence": tampered,
            "pending_evidence": pending,
            "unknown_evidence": unknown
        }

    @staticmethod
    def assemble_report_data(
        report: ReportRequest,
        db: Session,
        is_draft: bool = False
    ) -> Dict[str, Any]:
        """
        Synthesizes case records, resolves selected sections according to report type,
        reads existing hashes/verification outcomes without recalculation, and generates report.
        If is_draft=True, does NOT persist to database or create custody/audit events.
        """
        report_id = str(uuid4())
        now_utc = datetime.now(timezone.utc)
        case_id = report.case_id.strip()

        # Resolve active sections:
        # Distinguish selected_sections=None from explicitly empty list []
        if report.selected_sections is not None:
            # Validate unknown section names
            invalid_sections = [s for s in report.selected_sections if s not in ALL_REPORT_SECTIONS]
            if invalid_sections:
                raise ValueError(
                    f"Unknown report section name(s): {', '.join(invalid_sections)}. "
                    f"Valid sections are: {', '.join(sorted(ALL_REPORT_SECTIONS))}"
                )
            active_sections = list(report.selected_sections)
        else:
            active_sections = DEFAULT_SECTIONS_BY_TYPE.get(report.report_type, ALL_REPORT_SECTIONS)

        # Sync from adapter
        MetadataService.sync_case_from_adapter(db, case_id)
        CustodyService.sync_external_events(db, case_id=case_id)

        clean_ev_ids = set(str(x).strip() for x in report.evidence_ids) if report.evidence_ids else None

        # 1. Fetch Evidence Records
        query = db.query(EvidenceRecord).filter(EvidenceRecord.case_id == case_id)
        if clean_ev_ids:
            numeric_ids = [int(x) for x in clean_ev_ids if x.isdigit()]
            query = query.filter(
                (EvidenceRecord.external_evidence_id.in_(clean_ev_ids)) |
                (EvidenceRecord.id.in_(numeric_ids) if numeric_ids else False)
            )
        db_records = query.order_by(EvidenceRecord.id.asc()).all()

        evidence_records_data = []
        for r in db_records:
            cat, display = classify_file_type_display(r.original_filename, r.mime_type)
            evidence_records_data.append({
                "evidence_id": r.external_evidence_id or str(r.id),
                "case_id": r.case_id,
                "original_filename": r.original_filename,
                "file_type": r.evidence_type or display,
                "file_type_display": display,
                "file_category": cat,
                "file_size_bytes": r.file_size_bytes or 0,
                "file_size_formatted": format_bytes(r.file_size_bytes or 0),
                "uploaded_at": r.uploaded_at.isoformat() if r.uploaded_at else None,
                "created_at": r.created_at.isoformat() if r.created_at else None,
                "modified_at": r.modified_at.isoformat() if r.modified_at else None,
                # Existing hashes passed through, NEVER recalculated
                "original_sha256": r.original_sha256,
                "baseline_hash": r.original_sha256,
                "current_sha256": r.current_sha256,
                "current_hash": r.current_sha256,
                "verification_status": map_backend_verification_status(r.verification_status),
                "integrity_status": map_backend_verification_status(r.verification_status),
                "verification_timestamp": r.verification_timestamp.isoformat() if r.verification_timestamp else None,
                "verification_time": r.verification_timestamp.isoformat() if r.verification_timestamp else None,
                "verification_source": r.verification_source or "Shared Backend Integrity Subsystem"
            })

        # Summary Metrics - Keep Unknown and Error counts distinct
        total_ev = len(evidence_records_data)
        total_size = sum(e["file_size_bytes"] for e in evidence_records_data)
        distinct_types = len(set(e["file_type_display"] for e in evidence_records_data))

        verified_cnt = sum(1 for e in evidence_records_data if e["verification_status"] == "Verified")
        tampered_cnt = sum(1 for e in evidence_records_data if e["verification_status"] == "Tampered")
        pending_cnt = sum(1 for e in evidence_records_data if e["verification_status"] == "Pending")
        unknown_cnt = sum(1 for e in evidence_records_data if e["verification_status"] == "Unknown")
        error_cnt = sum(1 for e in evidence_records_data if e["verification_status"] == "Error")
        other_cnt = sum(1 for e in evidence_records_data if e["verification_status"] not in ("Verified", "Tampered", "Pending", "Unknown", "Error"))
        unknown_cnt += other_cnt

        latest_upload = None
        for e in evidence_records_data:
            if e["uploaded_at"] and (latest_upload is None or e["uploaded_at"] > latest_upload):
                latest_upload = e["uploaded_at"]

        evidence_summary = {
            "total_evidence": total_ev,
            "total_size_bytes": total_size,
            "total_size_formatted": format_bytes(total_size),
            "distinct_file_types": distinct_types,
            "latest_upload": latest_upload,
            "integrity_verified": verified_cnt,
            "integrity_match": verified_cnt,
            "integrity_tampered": tampered_cnt,
            "integrity_mismatch": tampered_cnt,
            "integrity_pending": pending_cnt,
            "integrity_not_verified": pending_cnt,
            "integrity_unknown": unknown_cnt,
            "integrity_error": error_cnt
        }

        # 2. Custody Logs - apply evidence scope
        custody_data = []
        if "chain_of_custody" in active_sections:
            c_query = db.query(CustodyLog).filter(CustodyLog.case_id == case_id)
            if clean_ev_ids:
                c_query = c_query.filter(
                    (CustodyLog.evidence_id.in_(clean_ev_ids)) |
                    (CustodyLog.evidence_id == None)
                )
            c_logs = c_query.order_by(CustodyLog.timestamp.asc(), CustodyLog.id.asc()).all()
            for c in c_logs:
                custody_data.append({
                    "id": c.id,
                    "evidence_id": c.evidence_id,
                    "event_type": c.event_type,
                    "title": c.title,
                    "action": c.action,
                    "actor_name": c.investigator_name,
                    "investigator_name": c.investigator_name,
                    "actor_role": c.actor_role,
                    "result": c.result,
                    "outcome": c.result,
                    "remarks": c.remarks,
                    "description": c.remarks,
                    "timestamp": c.timestamp.isoformat() if c.timestamp else None
                })

        # 3. Timeline - apply evidence scope
        timeline_data = []
        if "timeline" in active_sections:
            full_timeline = TimelineService.build_case_timeline(db, case_id)
            if clean_ev_ids:
                timeline_data = [
                    t for t in full_timeline
                    if t.get("evidence_id") is None or str(t.get("evidence_id")) in clean_ev_ids
                ]
            else:
                timeline_data = full_timeline

        # 4. Activity Logs - apply evidence scope
        activity_data = []
        if "activity_logs" in active_sections:
            a_query = db.query(ActivityLog).filter(ActivityLog.case_id == case_id)
            if clean_ev_ids:
                numeric_ids = [int(x) for x in clean_ev_ids if x.isdigit()]
                a_query = a_query.filter(
                    (ActivityLog.external_evidence_id.in_(clean_ev_ids)) |
                    (ActivityLog.evidence_id.in_(numeric_ids) if numeric_ids else False) |
                    ((ActivityLog.evidence_id == None) & (ActivityLog.external_evidence_id == None))
                )
            a_logs = a_query.order_by(ActivityLog.timestamp.asc(), ActivityLog.id.asc()).all()
            for a in a_logs:
                activity_data.append({
                    "investigator": a.investigator_name,
                    "investigator_name": a.investigator_name,
                    "action": a.action,
                    "activity": a.activity,
                    "outcome": a.outcome,
                    "details": a.details,
                    "time": a.timestamp.isoformat() if a.timestamp else None,
                    "timestamp": a.timestamp.isoformat() if a.timestamp else None
                })

        # 5. Suspect Records - apply evidence scope
        adapter = get_backend_adapter()
        suspect_records = []
        if "suspect_summary" in active_sections:
            source_suspects = report.suspect_records or adapter.get_suspects(case_id)
            for s in source_suspects:
                s_dict = s.model_dump() if hasattr(s, "model_dump") else dict(s)
                linked = [str(x) for x in s_dict.get("linked_evidence_ids", [])]
                if not clean_ev_ids or not linked or any(eid in clean_ev_ids for eid in linked):
                    suspect_records.append(s_dict)

        # 6. EPRA Analysis - apply evidence scope
        epra_analysis = []
        if "epra_analysis" in active_sections:
            adapter_epra = adapter.get_epra_analysis(case_id)
            for ep in adapter_epra:
                ep_dict = ep.model_dump() if hasattr(ep, "model_dump") else dict(ep)
                if not clean_ev_ids or str(ep_dict.get("evidence_id")) in clean_ev_ids:
                    epra_analysis.append(ep_dict)

        # Do not insert default crime/department as established facts
        adapter_case = adapter.get_case(case_id)
        effective_title = report.case_title or (adapter_case.case_title if adapter_case else None) or f"Case {case_id}"
        effective_crime = report.crime_type or (adapter_case.crime_type if adapter_case else None)
        effective_dept = report.department or (adapter_case.department if adapter_case else None)

        # Build combined report payload
        report_data = {
            "report_id": report_id,
            "case_id": case_id,
            "case_title": effective_title,
            "crime_type": effective_crime,
            "report_type": report.report_type.value if hasattr(report.report_type, "value") else str(report.report_type),
            "investigator_name": report.investigator_name,
            "investigator_id": report.investigator_id,
            "investigator_role": report.investigator_role,
            "department": effective_dept,
            "selected_sections": active_sections,
            "generated_at": now_utc.strftime("%d %b %Y, %H:%M:%S UTC"),
            "evidence_count": total_ev,
            "evidence_summary": evidence_summary,
            "evidence_records": evidence_records_data,
            "custody": custody_data,
            "timeline": timeline_data,
            "activity": activity_data,
            "suspect_records": suspect_records,
            "epra_analysis": epra_analysis,
            "conclusions_text": report.conclusions_text,
            "recommendations_text": report.recommendations_text,
            "is_draft": is_draft
        }

        # Handle Report Type 5: JSON Hash Manifest
        if report.report_type == ReportType.HASH_MANIFEST:
            manifest_json = {
                "manifest_version": "1.0.0",
                "report_id": report_id,
                "case_id": case_id,
                "case_title": report.case_title,
                "generated_at": now_utc.isoformat(),
                "generated_by": f"{report.investigator_name} ({report.investigator_role})",
                "hash_algorithm": "SHA-256",
                "total_evidence_files": total_ev,
                "evidence_hashes": [
                    {
                        "evidence_id": e["evidence_id"],
                        "original_filename": e["original_filename"],
                        "sha256": e["original_sha256"],
                        "current_sha256": e["current_sha256"],
                        "hash_status": "AVAILABLE" if e["original_sha256"] else "MISSING_HASH",
                        "verification_status": e["verification_status"]
                    }
                    for e in evidence_records_data
                ]
            }

            manifest_filename = f"manifest_{case_id}_{report_id}.json"
            import app.database as database
            manifest_file_path = database.MANIFEST_DIR / manifest_filename

            if not is_draft:
                manifest_file_path.write_text(json.dumps(manifest_json, indent=2), encoding="utf-8")
                rep_rec = ReportRecord(
                    id=report_id,
                    case_id=case_id,
                    case_title=report.case_title,
                    crime_type=report.crime_type,
                    investigator_name=report.investigator_name,
                    generated_by_id=report.investigator_id,
                    generated_by_role=report.investigator_role,
                    report_type=ReportType.HASH_MANIFEST.value,
                    file_format="JSON",
                    file_size_bytes=manifest_file_path.stat().st_size,
                    file_path=str(manifest_file_path.resolve()),
                    file_name=manifest_filename,
                    selected_sections=",".join(active_sections),
                    is_draft=False,
                    generated_at=now_utc
                )
                db.add(rep_rec)
                db.commit()

            return {
                "status": "success",
                "is_draft": is_draft,
                "report_id": report_id,
                "case_id": case_id,
                "report_type": ReportType.HASH_MANIFEST.value,
                "file_format": "JSON",
                "file_name": manifest_filename,
                "file_path": str(manifest_file_path.resolve()) if not is_draft else None,
                "manifest_content": manifest_json,
                "download_url": f"/report/download/{report_id}" if not is_draft else None,
                "evidence_summary": evidence_summary,
                "total_evidence_files": total_ev
            }

        # PDF Report Generation (Types 1-4)
        pdf_path = PDFService.generate_pdf(report_data, output_directory=str(REPORTS_DIR), is_draft=is_draft)
        file_path_obj = Path(pdf_path)
        file_size_bytes = file_path_obj.stat().st_size if file_path_obj.exists() else 0

        # Persist ONLY if not draft
        if not is_draft:
            rep_rec = ReportRecord(
                id=report_id,
                case_id=case_id,
                case_title=report.case_title,
                crime_type=report.crime_type,
                investigator_name=report.investigator_name,
                generated_by_id=report.investigator_id,
                generated_by_role=report.investigator_role,
                report_type=report_data["report_type"],
                file_format="PDF",
                file_size_bytes=file_size_bytes,
                file_path=str(file_path_obj.resolve()),
                file_name=file_path_obj.name,
                selected_sections=",".join(active_sections),
                is_draft=False,
                generated_at=now_utc
            )
            db.add(rep_rec)

            # Log custody inclusion for each evidence
            for ev in evidence_records_data:
                c_rep = CustodyLog(
                    evidence_id=str(ev["evidence_id"]),
                    case_id=case_id,
                    investigator_id=report.investigator_id,
                    investigator_name=report.investigator_name,
                    actor_role=report.investigator_role,
                    action="REPORT_GENERATED",
                    event_type="REPORT",
                    title="Included in Forensic Report",
                    result="SUCCESS",
                    remarks=f"Evidence included in {report_data['report_type']} (Report ID: {report_id}).",
                    related_reference=report_id,
                    is_system_action=False,
                    actor_is_unverified=False,
                    timestamp=now_utc
                )
                db.add(c_rep)

            # Log activity audit
            a_rep = ActivityLog(
                case_id=case_id,
                actor_id=report.investigator_id,
                investigator_name=report.investigator_name,
                action="REPORT_GENERATED",
                activity=f"Generated {report_data['report_type']} #{report_id}",
                outcome="SUCCESS",
                details=f"Format: PDF, Sections: {len(active_sections)}, Size: {format_bytes(file_size_bytes)}",
                timestamp=now_utc
            )
            db.add(a_rep)
            db.commit()

        return {
            "status": "success",
            "is_draft": is_draft,
            "message": "Draft preview generated successfully." if is_draft else "Report generated successfully.",
            "report_id": report_id,
            "case_id": case_id,
            "report_type": report_data["report_type"],
            "file_format": "PDF",
            "file_name": file_path_obj.name,
            "pdf_path": str(file_path_obj.resolve()),
            "download_url": f"/report/download/{report_id}" if not is_draft else None,
            "preview_url": f"/report/preview/{report_id}" if not is_draft else None,
            "evidence_summary": evidence_summary,
            "total_evidence_files": total_ev,
            "evidence_records": evidence_records_data,
            "selected_sections": active_sections,
            "crime_type": effective_crime,
            "department": effective_dept,
            "file_size_bytes": file_size_bytes,
            "file_size_formatted": format_bytes(file_size_bytes)
        }

    @staticmethod
    def get_report_history(db: Session, case_id: str, page: int = 1, page_size: int = 10) -> Dict[str, Any]:
        """
        Previous report history matching Section 8.E:
        - Report ID
        - Report Name
        - Generated-on timestamp
        - Generated-by identity
        - Report Type
        - File Format
        - Size
        - Preview URL
        - Download URL
        """
        clean_case_id = case_id.strip()
        query = db.query(ReportRecord).filter(
            ReportRecord.case_id == clean_case_id,
            ReportRecord.is_draft == False
        ).order_by(ReportRecord.generated_at.desc())

        total = query.count()
        offset = (max(1, page) - 1) * page_size
        records = query.offset(offset).limit(page_size).all()

        items = []
        for r in records:
            items.append({
                "report_id": r.id,
                "report_name": r.file_name,
                "case_id": r.case_id,
                "case_title": r.case_title,
                "crime_type": r.crime_type,
                "report_type": r.report_type,
                "file_format": r.file_format,
                "file_size_bytes": r.file_size_bytes,
                "file_size_formatted": format_bytes(r.file_size_bytes),
                "generated_at": r.generated_at.isoformat() if r.generated_at else None,
                "generated_at_formatted": r.generated_at.strftime("%d %b %Y, %H:%M") if r.generated_at else None,
                "generated_by": r.investigator_name,
                "generated_by_role": r.generated_by_role,
                "download_url": f"/report/download/{r.id}",
                "preview_url": f"/report/preview/{r.id}"
            })

        total_pages = (total + page_size - 1) // page_size if page_size > 0 else 1

        return {
            "case_id": clean_case_id,
            "total_reports": total,
            "page": page,
            "page_size": page_size,
            "total_pages": total_pages,
            "reports": items
        }