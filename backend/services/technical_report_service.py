import os
import json
from uuid import uuid4
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional, Dict, Any, List
from sqlalchemy.orm import Session
from sqlalchemy import func

from schemas.technical_report import (
    ReportRequest,
    ReportType,
    DEFAULT_SECTIONS_BY_TYPE,
    ALL_REPORT_SECTIONS,
    SuspectInput
)
from models.report_record import ReportRecord
from models.case import Case
from models.evidence import Evidence
from models.evidence_record import EvidenceRecord
from models.evidence_hash import EvidenceHash
from models.custody_log import CustodyLog
from models.activity_log import ActivityLog
from models.epra_result import EPRAResult
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.user import User

from services.timeline_service import TimelineService
from services.pdf_service import PDFService, DEFAULT_REPORTS_DIR

MANIFEST_DIR = DEFAULT_REPORTS_DIR.parent / "hash_manifests"
MANIFEST_DIR.mkdir(parents=True, exist_ok=True)


def format_bytes(num_bytes: int) -> str:
    """Format bytes into human-readable string."""
    if num_bytes is None or num_bytes == 0:
        return "0 B"
    units = ["B", "KB", "MB", "GB", "TB"]
    b = float(num_bytes)
    idx = 0
    while b >= 1024.0 and idx < len(units) - 1:
        b /= 1024.0
        idx += 1
    return f"{b:.1f} {units[idx]}" if idx > 0 else f"{int(b)} B"


def map_backend_verification_status(status: Optional[str]) -> str:
    """Normalize stored hash integrity status strings without recalculating hashes."""
    if not status:
        return "Unknown"
    s = str(status).strip().upper()
    if s in ("VERIFIED", "MATCH", "VALID"):
        return "Verified"
    elif s in ("TAMPERED", "MISMATCH", "CHANGED", "CORRUPTED"):
        return "Tampered"
    elif s in ("PENDING", "PENDING_VERIFICATION", "UNCHECKED"):
        return "Pending"
    elif s in ("ERROR", "FAILED"):
        return "Error"
    return "Unknown"


class TechnicalReportService:

    @staticmethod
    def get_case_reporting_summary(db: Session, case_id: str) -> Dict[str, Any]:
        """
        Derive Technical Report summary cards from real Case, Evidence, and EvidenceHash records:
        - Total Evidence
        - Verified Evidence (Hash status 'Verified' / 'MATCH')
        - Tampered Evidence (Hash status 'Tampered' / 'MISMATCH')
        - Pending Verification (Hash status 'Pending' / not yet checked)
        - Unknown / Error Outcome
        Never hardcodes counts.
        """
        clean_case_id = str(case_id).strip()
        num_case_id = int(clean_case_id) if clean_case_id.isdigit() else None

        # Fetch real evidence items for this case
        ev_query = db.query(Evidence)
        if num_case_id is not None:
            ev_query = ev_query.filter(Evidence.case_id == num_case_id)
        else:
            # Check case by case_id string
            case_obj = db.query(Case).filter(Case.case_id == clean_case_id).first()
            if case_obj:
                ev_query = ev_query.filter(Evidence.case_id == case_obj.id)
            else:
                ev_query = ev_query.filter(Evidence.case_id == -1)

        evidences = ev_query.all()
        total = len(evidences)
        verified = 0
        tampered = 0
        pending = 0
        unknown = 0

        for ev in evidences:
            # Check EvidenceHash
            h = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
            if h:
                st = map_backend_verification_status(h.integrity_status)
                if st == "Verified":
                    verified += 1
                elif st == "Tampered":
                    tampered += 1
                elif st == "Pending":
                    pending += 1
                else:
                    unknown += 1
            else:
                # Check EvidenceRecord
                er = db.query(EvidenceRecord).filter(
                    (EvidenceRecord.external_evidence_id == (ev.evidence_id or str(ev.id))) |
                    (EvidenceRecord.id == ev.id)
                ).first()
                if er and er.verification_status:
                    st = map_backend_verification_status(er.verification_status)
                    if st == "Verified":
                        verified += 1
                    elif st == "Tampered":
                        tampered += 1
                    elif st == "Pending":
                        pending += 1
                    else:
                        unknown += 1
                else:
                    pending += 1

        return {
            "case_id": clean_case_id,
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
        current_user: Optional[User] = None,
        is_draft: bool = False
    ) -> Dict[str, Any]:
        """
        Synthesizes genuine case records, resolves selected sections,
        reads existing hashes/verification outcomes without recalculation, and generates report.
        If is_draft=True, does NOT persist to database or create custody/audit events.
        """
        report_id = str(uuid4())
        now_utc = datetime.now(timezone.utc)
        case_id = str(report.case_id).strip()
        num_case_id = int(case_id) if case_id.isdigit() else None

        # Fetch genuine case details
        case_obj = None
        if num_case_id is not None:
            case_obj = db.query(Case).filter(Case.id == num_case_id).first()
        if not case_obj:
            case_obj = db.query(Case).filter(Case.case_id == case_id).first()

        effective_title = report.case_title or (case_obj.title if case_obj else None) or f"Case {case_id}"
        effective_crime = report.crime_type or (case_obj.description if case_obj and case_obj.description else None)
        effective_dept = report.department or "Cyber Crime Division"

        # Authoritative generator details derived strictly from JWT authenticated user
        if current_user:
            author_name = current_user.full_name or current_user.username
            author_id = str(current_user.id)
            author_role = "Cyber Expert" if current_user.role_id == 3 else ("Investigator" if current_user.role_id == 2 else "Administrator")
        else:
            author_name = report.investigator_name or "Investigator"
            author_id = report.investigator_id
            author_role = report.investigator_role or "Cyber Expert"

        # Resolve active sections:
        if report.selected_sections is not None:
            invalid_sections = [s for s in report.selected_sections if s not in ALL_REPORT_SECTIONS]
            if invalid_sections:
                raise ValueError(
                    f"Unknown report section name(s): {', '.join(invalid_sections)}. "
                    f"Valid sections are: {', '.join(sorted(ALL_REPORT_SECTIONS))}"
                )
            active_sections = list(report.selected_sections)
        else:
            active_sections = DEFAULT_SECTIONS_BY_TYPE.get(report.report_type, ALL_REPORT_SECTIONS)

        clean_ev_ids = set(str(x).strip() for x in report.evidence_ids) if report.evidence_ids else None

        # 1. Fetch Evidence & Integrity Details
        ev_query = db.query(Evidence)
        if case_obj:
            ev_query = ev_query.filter(Evidence.case_id == case_obj.id)
        elif num_case_id is not None:
            ev_query = ev_query.filter(Evidence.case_id == num_case_id)

        evidences = ev_query.order_by(Evidence.id.asc()).all()

        evidence_records_data = []
        for ev in evidences:
            ev_str_id = ev.evidence_id or str(ev.id)
            if clean_ev_ids and ev_str_id not in clean_ev_ids and str(ev.id) not in clean_ev_ids:
                continue

            # Fetch hash record without recomputing
            h = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
            er = db.query(EvidenceRecord).filter(
                (EvidenceRecord.external_evidence_id == ev_str_id) |
                (EvidenceRecord.id == ev.id)
            ).first()

            orig_hash = (h.sha256_hash if h else None) or (er.original_sha256 if er else None)
            curr_hash = (h.current_hash if h else None) or (er.current_sha256 if er else None) or orig_hash
            raw_status = (h.integrity_status if h else None) or (er.verification_status if er else None)
            v_status = map_backend_verification_status(raw_status)
            v_time = (h.verified_at if h else None) or (er.verification_timestamp if er else None)

            f_size = ev.file_size or (er.file_size_bytes if er else 0) or 0
            up_time = ev.created_at or (er.uploaded_at if er else None)

            evidence_records_data.append({
                "evidence_id": ev_str_id,
                "case_id": case_id,
                "original_filename": ev.file_name or (er.original_filename if er else "unknown"),
                "file_type": ev.file_type or (er.evidence_type if er else "FILE"),
                "file_size_bytes": f_size,
                "file_size_formatted": format_bytes(f_size),
                "uploaded_at": up_time.isoformat() if up_time else None,
                "original_sha256": orig_hash,
                "baseline_hash": orig_hash,
                "current_sha256": curr_hash,
                "current_hash": curr_hash,
                "verification_status": v_status,
                "integrity_status": v_status,
                "verification_timestamp": v_time.isoformat() if v_time else None,
                "verification_source": "Evidence Integrity Subsystem"
            })

        total_ev = len(evidence_records_data)
        total_size = sum(e["file_size_bytes"] for e in evidence_records_data)
        distinct_types = len(set(e["file_type"] for e in evidence_records_data))

        verified_cnt = sum(1 for e in evidence_records_data if e["verification_status"] == "Verified")
        tampered_cnt = sum(1 for e in evidence_records_data if e["verification_status"] == "Tampered")
        pending_cnt = sum(1 for e in evidence_records_data if e["verification_status"] == "Pending")
        unknown_cnt = sum(1 for e in evidence_records_data if e["verification_status"] not in ("Verified", "Tampered", "Pending"))

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
            "integrity_unknown": unknown_cnt
        }

        # 2. Custody Logs
        custody_data = []
        if "chain_of_custody" in active_sections:
            c_query = db.query(CustodyLog).filter(
                (CustodyLog.case_id == case_id) |
                (CustodyLog.case_id == str(case_obj.id) if case_obj else False)
            )
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
                    "title": c.title or c.action,
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

        # 3. Timeline Reconstruction
        timeline_data = []
        if "timeline" in active_sections:
            lookup_case_id = str(case_obj.id) if case_obj else case_id
            full_timeline = TimelineService.build_case_timeline(db, lookup_case_id)
            if clean_ev_ids:
                timeline_data = [
                    t for t in full_timeline
                    if t.get("evidence_id") is None or str(t.get("evidence_id")) in clean_ev_ids
                ]
            else:
                timeline_data = full_timeline

        # 4. Activity Logs
        activity_data = []
        if "activity_logs" in active_sections:
            a_query = db.query(ActivityLog).filter(
                (ActivityLog.case_id == case_id) |
                (ActivityLog.case_id == str(case_obj.id) if case_obj else False)
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

        # 5. Suspect Records (From PossibleEntity & Evidence Links)
        suspect_records = []
        if "suspect_summary" in active_sections:
            if report.suspect_records:
                for s in report.suspect_records:
                    suspect_records.append(s.model_dump() if hasattr(s, "model_dump") else dict(s))
            elif case_obj:
                pe_list = db.query(PossibleEntity).filter(
                    PossibleEntity.case_id == case_obj.id
                ).order_by(PossibleEntity.rank.asc()).all()

                for pe in pe_list:
                    # Deriving linked evidence IDs from relational links
                    link_rows = db.query(PossibleEntityEvidenceLink).filter(
                        PossibleEntityEvidenceLink.entity_id == pe.id
                    ).all()
                    linked_ids = []
                    for l in link_rows:
                        ev_item = db.query(Evidence).filter(Evidence.id == l.evidence_id).first()
                        linked_ids.append(ev_item.evidence_id if (ev_item and ev_item.evidence_id) else str(l.evidence_id))

                    suspect_records.append({
                        "suspect_id": pe.suspect_id,
                        "name": pe.suspect_name,
                        "role_or_relation": pe.entity_type or "Person of Interest",
                        "rank": pe.rank,
                        "externally_supplied_ranking": pe.rank,
                        "linked_evidence_ids": linked_ids,
                        "confidence_score": pe.confidence_score,
                        "notes": f"Total EPRA Score: {pe.total_epra_score:.2f}" if pe.total_epra_score is not None else ""
                    })

        # 6. EPRA Analysis Results (From EPRAResult model)
        epra_analysis = []
        if "epra_analysis" in active_sections and case_obj:
            epra_rows = db.query(EPRAResult).filter(
                EPRAResult.case_id == case_obj.id
            ).order_by(EPRAResult.rank.asc()).all()

            for erow in epra_rows:
                ev_match = db.query(Evidence).filter(Evidence.id == erow.evidence_id).first()
                ev_label = (ev_match.evidence_id if ev_match and ev_match.evidence_id else str(erow.evidence_id))
                if not clean_ev_ids or ev_label in clean_ev_ids or str(erow.evidence_id) in clean_ev_ids:
                    epra_analysis.append({
                        "evidence_id": ev_label,
                        "priority_rank": erow.rank,
                        "rank": erow.rank,
                        "priority_score": erow.epra_score,
                        "epra_score": erow.epra_score,
                        "status": erow.analysis_status or "MEASURED",
                        "priority": erow.priority,
                        "provenance_source": "EPRA Prioritization Model v2",
                        "notes": f"IPI: {erow.ipi:.4f}, Priority: {erow.priority}" if erow.ipi is not None else f"Priority: {erow.priority}"
                    })

        # Build combined report payload
        report_data = {
            "report_id": report_id,
            "case_id": case_id,
            "case_title": effective_title,
            "crime_type": effective_crime,
            "report_type": report.report_type.value if hasattr(report.report_type, "value") else str(report.report_type),
            "investigator_name": author_name,
            "investigator_id": author_id,
            "investigator_role": author_role,
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

        # Handle Report Type: JSON Hash Manifest
        if report.report_type == ReportType.HASH_MANIFEST:
            manifest_json = {
                "manifest_version": "1.0.0",
                "report_id": report_id,
                "case_id": case_id,
                "case_title": effective_title,
                "generated_at": now_utc.isoformat(),
                "generated_by": f"{author_name} ({author_role})",
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
            manifest_file_path = MANIFEST_DIR / manifest_filename

            if not is_draft:
                manifest_file_path.write_text(json.dumps(manifest_json, indent=2), encoding="utf-8")
                rep_rec = ReportRecord(
                    id=report_id,
                    case_id=case_id,
                    case_title=effective_title,
                    crime_type=effective_crime,
                    investigator_name=author_name,
                    generated_by_id=author_id,
                    generated_by_role=author_role,
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
                "message": "Draft preview generated successfully." if is_draft else "JSON Hash Manifest generated successfully.",
                "report_id": report_id,
                "case_id": case_id,
                "report_type": ReportType.HASH_MANIFEST.value,
                "file_format": "JSON",
                "file_name": manifest_filename,
                "file_path": str(manifest_file_path.resolve()) if not is_draft else None,
                "manifest_content": manifest_json,
                "download_url": f"/cases/{case_id}/reports/download/{report_id}" if not is_draft else None,
                "preview_url": f"/cases/{case_id}/reports/preview/{report_id}" if not is_draft else None,
                "evidence_summary": evidence_summary,
                "total_evidence_files": total_ev,
                "selected_sections": active_sections,
                "crime_type": effective_crime,
                "department": effective_dept,
                "file_size_bytes": manifest_file_path.stat().st_size if not is_draft else 0,
                "file_size_formatted": format_bytes(manifest_file_path.stat().st_size if not is_draft else 0)
            }

        # PDF Report Generation (All other report types)
        pdf_path = PDFService.generate_pdf(report_data, output_directory=str(DEFAULT_REPORTS_DIR), is_draft=is_draft)
        file_path_obj = Path(pdf_path)
        file_size_bytes = file_path_obj.stat().st_size if file_path_obj.exists() else 0

        if not is_draft:
            rep_rec = ReportRecord(
                id=report_id,
                case_id=case_id,
                case_title=effective_title,
                crime_type=effective_crime,
                investigator_name=author_name,
                generated_by_id=author_id,
                generated_by_role=author_role,
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

            # Record custody inclusion log for each evidence item
            for ev in evidence_records_data:
                c_rep = CustodyLog(
                    evidence_id=str(ev["evidence_id"]),
                    case_id=case_id,
                    investigator_id=author_id,
                    investigator_name=author_name,
                    actor_role=author_role,
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

            # Record activity audit log
            a_rep = ActivityLog(
                case_id=case_id,
                actor_id=author_id,
                investigator_name=author_name,
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
            "download_url": f"/cases/{case_id}/reports/download/{report_id}" if not is_draft else None,
            "preview_url": f"/cases/{case_id}/reports/preview/{report_id}" if not is_draft else None,
            "evidence_summary": evidence_summary,
            "total_evidence_files": total_ev,
            "selected_sections": active_sections,
            "crime_type": effective_crime,
            "department": effective_dept,
            "file_size_bytes": file_size_bytes,
            "file_size_formatted": format_bytes(file_size_bytes)
        }

    @staticmethod
    def get_report_history(db: Session, case_id: str, page: int = 1, page_size: int = 10) -> Dict[str, Any]:
        """
        Previous report history matching UI specifications:
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
        clean_case_id = str(case_id).strip()
        num_case_id = int(clean_case_id) if clean_case_id.isdigit() else None

        # Resolve case to support both numeric ID and string case_id
        case_obj = None
        if num_case_id is not None:
            case_obj = db.query(Case).filter(Case.id == num_case_id).first()
        if not case_obj:
            case_obj = db.query(Case).filter(Case.case_id == clean_case_id).first()

        match_ids = [clean_case_id]
        if case_obj:
            match_ids.append(str(case_obj.id))
            if case_obj.case_id:
                match_ids.append(str(case_obj.case_id))
        match_ids = list(set(match_ids))

        query = db.query(ReportRecord).filter(
            ReportRecord.case_id.in_(match_ids),
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
                "case_id": clean_case_id,
                "case_title": r.case_title,
                "crime_type": r.crime_type,
                "report_type": r.report_type,
                "file_format": r.file_format,
                "file_size_bytes": r.file_size_bytes or 0,
                "file_size_formatted": format_bytes(r.file_size_bytes or 0),
                "generated_at": r.generated_at.isoformat() if r.generated_at else None,
                "generated_at_formatted": r.generated_at.strftime("%d %b %Y, %H:%M") if r.generated_at else None,
                "generated_by": r.investigator_name,
                "generated_by_role": r.generated_by_role,
                "download_url": f"/cases/{clean_case_id}/reports/download/{r.id}",
                "preview_url": f"/cases/{clean_case_id}/reports/preview/{r.id}"
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
