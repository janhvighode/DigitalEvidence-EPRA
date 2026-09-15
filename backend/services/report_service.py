import os
from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple
from datetime import datetime, timezone, timedelta
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import or_, and_, func

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.evidence_record import EvidenceRecord
from models.epra_result import EPRAResult
from models.custody_log import CustodyLog
from models.case_timeline import CaseTimeline
from models.activity_log import ActivityLog
from models.cbir_result import CBIRResult
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.report_record import ReportRecord

from services.pdf_service import PDFService, DEFAULT_REPORTS_DIR
from services.technical_report_service import (
    TechnicalReportService,
    format_bytes,
    map_backend_verification_status
)


# ==============================================================================
# AUTHORIZATION HELPER
# ==============================================================================

def verify_case_access_for_user(case: Case, current_user: User) -> bool:
    """
    Strictly verifies if current_user is authorized for this case:
    - Admin (role_id == 1): must match cyber_cell_id
    - Investigator (role_id == 2): case.investigator_id == current_user.id
    - Cyber Expert (role_id == 3): case.cyber_expert_id == current_user.id
    """
    if not current_user:
        return False
    if current_user.role_id == 2:
        return case.investigator_id == current_user.id
    elif current_user.role_id == 3:
        return case.cyber_expert_id == current_user.id
    elif current_user.role_id == 1:
        if current_user.cyber_cell_id is None:
            return True
        creator = case.creator if hasattr(case, "creator") else None
        if creator and creator.cyber_cell_id:
            return creator.cyber_cell_id == current_user.cyber_cell_id
        return True
    return False


def get_scoped_case_query(db: Session, current_user: User):
    """Returns a base SQLAlchemy query for cases strictly scoped to current_user."""
    query = db.query(Case)
    if current_user.role_id == 2:
        query = query.filter(Case.investigator_id == current_user.id)
    elif current_user.role_id == 3:
        query = query.filter(Case.cyber_expert_id == current_user.id)
    elif current_user.role_id == 1:
        if current_user.cyber_cell_id is not None:
            creator = User.__table__.alias("creator")
            query = query.join(creator, Case.created_by == creator.c.id).filter(
                creator.c.cyber_cell_id == current_user.cyber_cell_id
            )
    else:
        query = query.filter(Case.id == -1)
    return query


# ==============================================================================
# 1. REPORTS OVERVIEW COUNTS
# ==============================================================================

def get_investigator_reports_overview(db: Session, current_user: User) -> Dict[str, int]:
    """
    Aggregated report counts strictly derived from genuine database records:
    - Total Reports (finalized reports generated for user's assigned cases)
    - Ongoing Reports (assigned active cases that have a generated report)
    - Completed / Final Reports (assigned closed cases with reports or final reports)
    - Draft Reports (assigned cases with only draft reports)
    - Not Generated Reports (assigned cases without any report)
    """
    cases = get_scoped_case_query(db, current_user).all()

    total_reports = 0
    ongoing_reports = 0
    completed_final_reports = 0
    draft_reports = 0
    not_generated_reports = 0

    for case in cases:
        case_match_ids = [str(case.case_id), str(case.id)]
        reports = db.query(ReportRecord).filter(
            ReportRecord.case_id.in_(case_match_ids)
        ).order_by(ReportRecord.generated_at.desc()).all()

        final_rep = next((r for r in reports if not r.is_draft), None)
        draft_rep = next((r for r in reports if r.is_draft), None)

        if final_rep:
            total_reports += 1
            if case.status == "Closed":
                completed_final_reports += 1
            else:
                ongoing_reports += 1
        elif draft_rep:
            draft_reports += 1
        else:
            not_generated_reports += 1

    return {
        "total_reports": total_reports,
        "ongoing_reports": ongoing_reports,
        "completed_final_reports": completed_final_reports,
        "draft_reports": draft_reports,
        "not_generated_reports": not_generated_reports
    }


# ==============================================================================
# 2. REPORTS TREND (LAST 6 MONTHS)
# ==============================================================================

def get_investigator_reports_trend(db: Session, current_user: User) -> List[Dict[str, Any]]:
    """
    Calculates monthly report generation trends over the past 6 calendar months:
    - Month name (e.g. 'Apr 2026')
    - Reports Generated (count of reports generated in that month)
    - Final Reports (count of finalized/completed reports in that month)
    Derived strictly from real ReportRecord timestamps scoped to assigned cases.
    """
    now = datetime.now(timezone.utc)
    cases = get_scoped_case_query(db, current_user).all()
    case_ids_set = set()
    for c in cases:
        case_ids_set.add(str(c.case_id))
        case_ids_set.add(str(c.id))

    # Generate 6 month slots ending at current month
    month_slots = []
    # Work backwards 5 months to current month
    cur_year = now.year
    cur_month = now.month

    for i in range(5, -1, -1):
        # Calculate year and month for offset i
        m = cur_month - i
        y = cur_year
        while m <= 0:
            m += 12
            y -= 1
        month_slots.append((y, m))

    trend_data = []

    if not case_ids_set:
        for y, m in month_slots:
            dt = datetime(y, m, 1)
            trend_data.append({
                "month": dt.strftime("%b %Y"),
                "year": y,
                "reports_generated": 0,
                "final_reports": 0
            })
        return trend_data

    # Query all reports for assigned cases
    all_reports = db.query(ReportRecord).filter(
        ReportRecord.case_id.in_(list(case_ids_set))
    ).all()

    # Map case closed dates for accurate final report attribution
    case_closed_map = {str(c.case_id): (c.status == "Closed") for c in cases}
    for c in cases:
        case_closed_map[str(c.id)] = (c.status == "Closed")

    for y, m in month_slots:
        dt_label = datetime(y, m, 1).strftime("%b %Y")
        gen_count = 0
        final_count = 0

        for r in all_reports:
            if not r.generated_at:
                continue
            r_dt = r.generated_at
            if r_dt.tzinfo is None:
                r_dt = r_dt.replace(tzinfo=timezone.utc)
            if r_dt.year == y and r_dt.month == m:
                if not r.is_draft:
                    gen_count += 1
                    if case_closed_map.get(str(r.case_id), False):
                        final_count += 1

        trend_data.append({
            "month": dt_label,
            "year": y,
            "reports_generated": gen_count,
            "final_reports": final_count
        })

    return trend_data


# ==============================================================================
# 3. REPORTS TABLE (SEARCH, FILTER, PAGINATION)
# ==============================================================================

def calculate_investigation_progress(case: Case, has_evidence: bool, has_verified: bool, has_epra: bool, has_report: bool) -> int:
    """Computes genuine investigation progress percentage based on completed milestones."""
    if case.status == "Closed":
        return 100
    progress = 20  # Base: Case registered
    if has_evidence:
        progress += 20
    if has_verified:
        progress += 20
    if has_epra:
        progress += 20
    if has_report:
        progress += 20
    return min(progress, 100)


def get_investigator_reports_table(
    db: Session,
    current_user: User,
    keyword: Optional[str] = None,
    case_status: Optional[str] = None,
    report_status: Optional[str] = None,
    crime_type: Optional[str] = None,
    date_from: Optional[str] = None,
    date_to: Optional[str] = None,
    page: int = 1,
    page_size: int = 10
) -> Dict[str, Any]:
    """
    Returns filtered, searchable, paginated table of cases & reports strictly assigned to current_user.
    Columns: Case ID, Case Name, Crime Type, Case Status, Report Status, Progress, Last Updated, Actions.
    """
    query = get_scoped_case_query(db, current_user)

    # Filter by Case Status
    if case_status and case_status.strip() and case_status.upper() != "ALL":
        query = query.filter(Case.status == case_status.strip())

    # Filter by Keyword
    if keyword and keyword.strip():
        kw = f"%{keyword.strip()}%"
        query = query.filter(
            or_(
                Case.case_id.ilike(kw),
                Case.title.ilike(kw),
                Case.description.ilike(kw)
            )
        )

    # Filter by Date range
    if date_from and date_from.strip():
        try:
            d_from = datetime.fromisoformat(date_from.strip().replace("Z", "+00:00"))
            query = query.filter(Case.created_at >= d_from)
        except Exception:
            pass
    if date_to and date_to.strip():
        try:
            d_to = datetime.fromisoformat(date_to.strip().replace("Z", "+00:00"))
            query = query.filter(Case.created_at <= d_to)
        except Exception:
            pass

    # Order by newest case first
    cases = query.order_by(Case.created_at.desc()).all()

    # Preload report records for these cases to avoid N+1 queries
    case_id_strings = []
    for c in cases:
        case_id_strings.append(str(c.case_id))
        case_id_strings.append(str(c.id))

    all_case_reports = db.query(ReportRecord).filter(
        ReportRecord.case_id.in_(case_id_strings)
    ).order_by(ReportRecord.generated_at.desc()).all() if case_id_strings else []

    reports_by_case: Dict[str, List[ReportRecord]] = {}
    for r in all_case_reports:
        reports_by_case.setdefault(str(r.case_id), []).append(r)

    # Preload evidence counts & statuses
    evidence_counts = db.query(
        Evidence.case_id,
        func.count(Evidence.id).label("total_ev")
    ).group_by(Evidence.case_id).all()
    ev_count_map = {row[0]: row[1] for row in evidence_counts}

    epra_counts = db.query(
        EPRAResult.case_id,
        func.count(EPRAResult.id).label("total_epra")
    ).group_by(EPRAResult.case_id).all()
    epra_count_map = {row[0]: row[1] for row in epra_counts}

    table_rows = []

    for case in cases:
        # Match reports
        matched_reports = (
            reports_by_case.get(str(case.case_id), []) +
            reports_by_case.get(str(case.id), [])
        )
        # Deduplicate by report id
        unique_reps = {r.id: r for r in matched_reports}.values()
        sorted_reps = sorted(unique_reps, key=lambda x: x.generated_at or datetime.min, reverse=True)

        final_rep = next((r for r in sorted_reps if not r.is_draft), None)
        draft_rep = next((r for r in sorted_reps if r.is_draft), None)

        active_rep = final_rep or draft_rep

        if final_rep:
            r_status = "FINAL" if case.status == "Closed" else "GENERATED"
        elif draft_rep:
            r_status = "DRAFT"
        else:
            r_status = "NOT_GENERATED"

        # Filter by Report Status if requested
        if report_status and report_status.strip() and report_status.upper() != "ALL":
            target_status = report_status.strip().upper()
            if target_status == "COMPLETED" or target_status == "FINAL":
                if r_status != "FINAL":
                    continue
            elif target_status == "ONGOING" or target_status == "GENERATED":
                if r_status != "GENERATED":
                    continue
            elif target_status == "DRAFT":
                if r_status != "DRAFT":
                    continue
            elif target_status == "NOT_GENERATED":
                if r_status != "NOT_GENERATED":
                    continue
            elif r_status != target_status:
                continue

        # Filter by Crime Type if requested
        c_crime = case.description or "General Cyber Crime"
        if crime_type and crime_type.strip() and crime_type.upper() != "ALL":
            if crime_type.strip().lower() not in c_crime.lower() and crime_type.strip().lower() not in (case.title or "").lower():
                continue

        has_ev = (ev_count_map.get(case.id, 0) > 0)
        has_epra = (epra_count_map.get(case.id, 0) > 0) or (epra_count_map.get(str(case.case_id), 0) > 0)
        has_report = (final_rep is not None)
        progress = calculate_investigation_progress(case, has_ev, has_ev, has_epra, has_report)

        last_up = (active_rep.generated_at if active_rep else None) or case.updated_at or case.created_at
        last_up_disp = last_up.strftime("%d %b %Y %H:%M") if last_up else None

        rep_id = active_rep.id if active_rep else None
        can_view = (r_status in ("GENERATED", "FINAL", "DRAFT"))
        can_download = (r_status in ("GENERATED", "FINAL"))

        table_rows.append({
            "case_id": case.case_id,
            "case_name": case.title or f"Case #{case.case_id}",
            "crime_type": c_crime,
            "case_status": case.status,
            "report_status": r_status,
            "investigation_progress": progress,
            "last_updated": last_up,
            "last_updated_display": last_up_disp,
            "report_id": rep_id,
            "download_url": f"/reports/{rep_id}/download" if can_download and rep_id else (
                f"/cases/{case.case_id}/reports/download/{rep_id}" if can_download and rep_id else None
            ),
            "view_url": f"/reports/{rep_id}/view" if can_view and rep_id else f"/reports/{case.case_id}/view",
            "can_view": can_view,
            "can_download": can_download
        })

    total_count = len(table_rows)
    total_pages = max(1, (total_count + page_size - 1) // page_size)
    start_idx = (page - 1) * page_size
    end_idx = start_idx + page_size
    paginated_items = table_rows[start_idx:end_idx]

    return {
        "total_count": total_count,
        "total_pages": total_pages,
        "page": page,
        "page_size": page_size,
        "items": paginated_items
    }


# ==============================================================================
# 4. VIEW REPORT (FULL STRUCTURED REPORT WITH ALL 12+ FORENSIC SECTIONS)
# ==============================================================================

def get_report_view_data(db: Session, case_or_report_id: str, current_user: User) -> Dict[str, Any]:
    """
    Retrieves the complete structured report data for View Report modal/screen.
    Supports either report_id (UUID) or case_id (e.g. 'CASE-2015' or numeric ID).
    Strictly verifies authorization against current_user.
    Renders genuine data across all sections; uses 'Pending Analysis' for missing data without fabricating.
    """
    clean_id = str(case_or_report_id).strip()

    # 1. Try finding ReportRecord by ID first
    rep_rec = db.query(ReportRecord).filter(ReportRecord.id == clean_id).first()
    case_obj = None

    if rep_rec:
        # Find parent case
        case_id_val = rep_rec.case_id
        if case_id_val.isdigit():
            case_obj = db.query(Case).filter((Case.id == int(case_id_val)) | (Case.case_id == case_id_val)).first()
        else:
            case_obj = db.query(Case).filter(Case.case_id == case_id_val).first()
    else:
        # Check by case_id
        if clean_id.isdigit():
            case_obj = db.query(Case).filter((Case.id == int(clean_id)) | (Case.case_id == clean_id)).first()
        else:
            case_obj = db.query(Case).filter(Case.case_id == clean_id).first()

        if case_obj:
            match_ids = [str(case_obj.case_id), str(case_obj.id)]
            rep_rec = db.query(ReportRecord).filter(
                ReportRecord.case_id.in_(match_ids)
            ).order_by(ReportRecord.is_draft.asc(), ReportRecord.generated_at.desc()).first()

    if not case_obj:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Case or report '{case_or_report_id}' not found."
        )

    # 2. Strict Authorization Check
    if not verify_case_access_for_user(case_obj, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Access denied: You are not authorized to view reports for Case #{case_obj.case_id}."
        )

    # 3. Determine Report Status
    if rep_rec:
        if rep_rec.is_draft:
            r_status = "DRAFT"
        elif case_obj.status == "Closed":
            r_status = "FINAL"
        else:
            r_status = "GENERATED"
    else:
        r_status = "NOT_GENERATED"

    # 4. Fetch Case Investigator and Cyber Expert
    inv_user = db.query(User).filter(User.id == case_obj.investigator_id).first() if case_obj.investigator_id else None
    exp_user = db.query(User).filter(User.id == case_obj.cyber_expert_id).first() if case_obj.cyber_expert_id else None

    # 5. Fetch Genuine Evidence Records
    ev_list = db.query(Evidence).filter(Evidence.case_id == case_obj.id).order_by(Evidence.id.asc()).all()
    ev_metadata_items = []
    total_size_bytes = 0
    verified_count = 0
    tampered_count = 0
    pending_count = 0

    for ev in ev_list:
        ev_str = ev.evidence_id or str(ev.id)
        h = db.query(EvidenceHash).filter(EvidenceHash.evidence_id == ev.id).first()
        er = db.query(EvidenceRecord).filter(
            (EvidenceRecord.external_evidence_id == ev_str) | (EvidenceRecord.id == ev.id)
        ).first()

        orig_h = (h.sha256_hash if h else None) or (er.original_sha256 if er else None)
        curr_h = (h.current_hash if h else None) or (er.current_sha256 if er else None) or orig_h
        raw_st = (h.integrity_status if h else None) or (er.verification_status if er else None)
        norm_st = map_backend_verification_status(raw_st)

        if norm_st == "Verified":
            verified_count += 1
        elif norm_st == "Tampered":
            tampered_count += 1
        else:
            pending_count += 1

        f_size = ev.file_size or (er.file_size_bytes if er else 0) or 0
        total_size_bytes += f_size
        up_time = ev.created_at or (er.uploaded_at if er else None)

        ev_metadata_items.append({
            "evidence_id": ev_str,
            "filename": ev.file_name or (er.original_filename if er else "unknown"),
            "file_type": ev.file_type or (er.evidence_type if er else "FILE"),
            "file_size": format_bytes(f_size),
            "file_size_bytes": f_size,
            "uploaded_at": up_time.isoformat() if up_time else None,
            "uploaded_at_display": up_time.strftime("%d %b %Y %H:%M") if up_time else "N/A",
            "sha256_hash": curr_h,
            "baseline_hash": orig_h,
            "hash_status": norm_st
        })

    # 6. Fetch Genuine Chain of Custody Logs
    c_logs = db.query(CustodyLog).filter(
        (CustodyLog.case_id == str(case_obj.id)) | (CustodyLog.case_id == str(case_obj.case_id))
    ).order_by(CustodyLog.timestamp.asc()).all()

    custody_entries = []
    for cl in c_logs:
        custody_entries.append({
            "timestamp": cl.timestamp.isoformat() if cl.timestamp else None,
            "timestamp_display": cl.timestamp.strftime("%d %b %Y %H:%M") if cl.timestamp else "N/A",
            "action": cl.action,
            "performed_by": cl.investigator_name or "System",
            "role": cl.actor_role or "Investigator",
            "remarks": cl.remarks or cl.title or "Custody action logged",
            "result": cl.result or "SUCCESS"
        })

    # 7. Fetch Genuine EPRA Results
    epra_items = db.query(EPRAResult).filter(
        (EPRAResult.case_id == case_obj.id) | (EPRAResult.case_id == case_obj.case_id)
    ).all()
    epra_data = []
    for ep in epra_items:
        score_val = getattr(ep, "epra_score", None) or getattr(ep, "ipi", None)
        cat_val = getattr(ep, "category", None) or getattr(ep, "relevance_reason", None)
        a_at = getattr(ep, "analyzed_at", None)
        epra_data.append({
            "evidence_id": ep.evidence_id,
            "score": score_val,
            "priority": getattr(ep, "priority", "Medium"),
            "category": cat_val,
            "analyzed_at": a_at.isoformat() if a_at else None
        })

    # 8. Fetch Genuine CBIR Results
    cbir_items = db.query(CBIRResult).filter(
        (CBIRResult.case_id == case_obj.id) | (CBIRResult.case_id == case_obj.case_id)
    ).all()
    cbir_data = []
    for cb in cbir_items:
        cbir_data.append({
            "evidence_id": cb.evidence_id,
            "similarity_score": cb.similarity_score,
            "matched_category": cb.matched_category,
            "status": cb.status
        })

    # 9. Fetch Genuine Suspect / Entity Data
    entities = db.query(PossibleEntity).filter(
        (PossibleEntity.case_id == case_obj.id) | (PossibleEntity.case_id == case_obj.case_id)
    ).all()
    suspect_data = []
    for en in entities:
        suspect_data.append({
            "entity_name": en.name,
            "entity_type": en.entity_type,
            "confidence_score": en.confidence_score,
            "priority": en.priority,
            "status": en.status
        })

    # 10. Fetch Case Timeline Events
    timelines = db.query(CaseTimeline).filter(
        CaseTimeline.case_id == case_obj.id
    ).order_by(CaseTimeline.created_at.asc()).all()
    timeline_data = []
    for tm in timelines:
        timeline_data.append({
            "event": tm.event,
            "role": tm.performed_by_role,
            "timestamp": tm.created_at.isoformat() if tm.created_at else None,
            "timestamp_display": tm.created_at.strftime("%d %b %Y %H:%M") if tm.created_at else "N/A"
        })

    can_download = (r_status in ("GENERATED", "FINAL") and rep_rec is not None)
    download_url = f"/reports/{rep_rec.id}/download" if can_download and rep_rec else None

    gen_time = rep_rec.generated_at if rep_rec else None
    gen_time_disp = gen_time.strftime("%d %b %Y %H:%M") if gen_time else None

    return {
        "report_id": rep_rec.id if rep_rec else None,
        "case_id": case_obj.case_id,
        "case_title": case_obj.title or f"Case #{case_obj.case_id}",
        "crime_type": case_obj.description or "General Cyber Crime",
        "case_status": case_obj.status,
        "priority": case_obj.priority or "Medium",
        "report_status": r_status,
        "is_draft": rep_rec.is_draft if rep_rec else False,
        "generated_at": gen_time,
        "generated_at_display": gen_time_disp,
        "investigator_name": inv_user.full_name if inv_user else "Unassigned",
        "investigator_id": str(case_obj.investigator_id) if case_obj.investigator_id else None,
        "assigned_cyber_expert": exp_user.full_name if exp_user else "Unassigned",

        # 1. Report Information
        "report_info": {
            "report_id": rep_rec.id if rep_rec else "N/A",
            "report_type": rep_rec.report_type if rep_rec else "Comprehensive Forensic Report",
            "file_format": rep_rec.file_format if rep_rec else "PDF",
            "file_size": format_bytes(rep_rec.file_size_bytes) if rep_rec else "0 B",
            "generated_by": rep_rec.investigator_name if rep_rec else "System",
            "generated_by_role": rep_rec.generated_by_role if rep_rec else "Investigator",
            "generated_at": gen_time_disp or "Not yet generated"
        },

        # 2. Case Information
        "case_information": {
            "case_id": case_obj.case_id,
            "title": case_obj.title,
            "description": case_obj.description,
            "priority": case_obj.priority,
            "status": case_obj.status,
            "created_at": case_obj.created_at.strftime("%d %b %Y %H:%M") if case_obj.created_at else None,
            "updated_at": case_obj.updated_at.strftime("%d %b %Y %H:%M") if case_obj.updated_at else None
        },

        # 3. Investigator Information
        "investigator_information": {
            "name": inv_user.full_name if inv_user else "Unassigned",
            "username": inv_user.username if inv_user else "N/A",
            "email": inv_user.email if inv_user else "N/A"
        },

        # 4. Assigned Cyber Expert
        "cyber_expert_information": {
            "name": exp_user.full_name if exp_user else "Unassigned",
            "username": exp_user.username if exp_user else "N/A",
            "email": exp_user.email if exp_user else "N/A"
        },

        # 5. Evidence Summary
        "evidence_summary": {
            "total_evidence": len(ev_list),
            "total_size": format_bytes(total_size_bytes),
            "total_size_bytes": total_size_bytes,
            "verified_count": verified_count,
            "tampered_count": tampered_count,
            "pending_count": pending_count
        },

        # 6. Evidence Metadata
        "evidence_metadata": ev_metadata_items,

        # 7. SHA-256 / Integrity Verification
        "integrity_verification": {
            "verified_count": verified_count,
            "tampered_count": tampered_count,
            "pending_count": pending_count,
            "status": "TAMPERED_DETECTED" if tampered_count > 0 else ("VERIFIED_MATCH" if verified_count > 0 and pending_count == 0 else "PENDING_VERIFICATION"),
            "audit_summary": f"{verified_count} evidence items verified matching cryptographic baselines; {tampered_count} tampered files detected."
        },

        # 8. Chain of Custody
        "chain_of_custody": {
            "status": "COMPLETED" if custody_entries else "Pending Analysis",
            "events_count": len(custody_entries),
            "logs": custody_entries if custody_entries else []
        },

        # 9. EPRA Results
        "epra_analysis": {
            "status": "COMPLETED" if epra_data else "Pending Analysis",
            "analyzed_count": len(epra_data),
            "results": epra_data if epra_data else []
        },

        # 10. CBIR Results
        "cbir_analysis": {
            "status": "COMPLETED" if cbir_data else "Pending Analysis",
            "matched_count": len(cbir_data),
            "results": cbir_data if cbir_data else []
        },

        # 11. Suspect Ranking
        "suspect_ranking": {
            "status": "COMPLETED" if suspect_data else "Pending Analysis",
            "suspects_count": len(suspect_data),
            "suspects": suspect_data if suspect_data else []
        },

        # 12. Relationship Analysis
        "relationship_analysis": {
            "status": "COMPLETED" if (epra_data or suspect_data) else "Pending Analysis",
            "nodes_count": len(ev_list) + len(suspect_data),
            "details": "Entity connection graph available in workspace" if (epra_data or suspect_data) else "Pending Analysis"
        },

        # 13. Timeline Reconstruction
        "timeline_reconstruction": {
            "status": "COMPLETED" if timeline_data else "Pending Analysis",
            "events_count": len(timeline_data),
            "events": timeline_data if timeline_data else []
        },

        # 14. Investigation Findings
        "investigation_findings": {
            "case_status": case_obj.status,
            "evidence_analyzed": len(ev_list),
            "integrity_standing": "All evidence verified intact" if tampered_count == 0 and verified_count > 0 else ("Tampered evidence requires legal review" if tampered_count > 0 else "Forensic verification in progress"),
            "summary": f"Investigation for case {case_obj.case_id} contains {len(ev_list)} catalogued evidence artifacts with {verified_count} cryptographic verifications."
        },

        # 15. Conclusion
        "conclusion": {
            "status": "FINAL_CLOSED" if case_obj.status == "Closed" else "ONGOING_INVESTIGATION",
            "text": f"This forensic report serves as an official technical evidentiary record for Case #{case_obj.case_id}. Case is currently '{case_obj.status}'."
        },

        "download_url": download_url,
        "file_name": rep_rec.file_name if rep_rec else f"{case_obj.case_id}_Forensic_Report.pdf",
        "can_download": can_download
    }


# ==============================================================================
# 5. CENTRALIZED DOWNLOAD PDF HELPER
# ==============================================================================

def get_report_pdf_file_path(db: Session, report_or_case_id: str, current_user: User) -> Tuple[Path, str]:
    """
    Safely resolves and returns the persistent PDF Path and downloaded filename.
    If report is NOT_GENERATED -> HTTP 400 Bad Request.
    If unauthorized -> HTTP 403 Forbidden.
    If PDF file on disk is missing -> Regenerates the valid persistent PDF and updates path.
    """
    clean_id = str(report_or_case_id).strip()

    # 1. Try finding ReportRecord by ID first
    rep_rec = db.query(ReportRecord).filter(ReportRecord.id == clean_id).first()
    case_obj = None

    if rep_rec:
        case_id_val = rep_rec.case_id
        if case_id_val.isdigit():
            case_obj = db.query(Case).filter((Case.id == int(case_id_val)) | (Case.case_id == case_id_val)).first()
        else:
            case_obj = db.query(Case).filter(Case.case_id == case_id_val).first()
    else:
        # Check by case_id
        if clean_id.isdigit():
            case_obj = db.query(Case).filter((Case.id == int(clean_id)) | (Case.case_id == clean_id)).first()
        else:
            case_obj = db.query(Case).filter(Case.case_id == clean_id).first()

        if case_obj:
            match_ids = [str(case_obj.case_id), str(case_obj.id)]
            rep_rec = db.query(ReportRecord).filter(
                ReportRecord.case_id.in_(match_ids),
                ReportRecord.is_draft == False
            ).order_by(ReportRecord.generated_at.desc()).first()

    if not case_obj:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Case or report '{report_or_case_id}' not found."
        )

    # 2. Strict Authorization Check
    if not verify_case_access_for_user(case_obj, current_user):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"Access denied: You are not authorized to download reports for Case #{case_obj.case_id}."
        )

    # 3. If no report record exists -> NOT_GENERATED -> Never download fake PDF!
    if not rep_rec:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Report has not been generated for this case. Download is unavailable."
        )

    # 4. Check if file exists on disk
    target_path = Path(rep_rec.file_path).resolve() if rep_rec.file_path else None
    resolved_root = DEFAULT_REPORTS_DIR.parent.resolve()

    if target_path and target_path.exists() and target_path.is_file() and target_path.stat().st_size > 0:
        download_filename = f"{case_obj.case_id}_Forensic_Report.pdf"
        return target_path, download_filename

    # If file was missing on disk, regenerate persistent PDF safely
    from schemas.technical_report import ReportRequest
    req = ReportRequest(case_id=str(case_obj.case_id))
    gen_result = TechnicalReportService.assemble_report_data(
        report=req,
        db=db,
        current_user=current_user,
        is_draft=rep_rec.is_draft
    )
    new_pdf_path = Path(gen_result["pdf_path"]).resolve()
    rep_rec.file_path = str(new_pdf_path)
    rep_rec.file_size_bytes = new_pdf_path.stat().st_size
    db.commit()

    download_filename = f"{case_obj.case_id}_Forensic_Report.pdf"
    return new_pdf_path, download_filename


# ==============================================================================
# 6. LEGACY BACKWARD COMPATIBILITY
# ==============================================================================

def get_completed_reports(db: Session, current_user: User):
    """Legacy endpoint returning list of completed reports."""
    table_data = get_investigator_reports_table(
        db=db,
        current_user=current_user,
        report_status="FINAL",
        page=1,
        page_size=100
    )
    result = []
    for item in table_data["items"]:
        result.append({
            "case_id": item["case_id"],
            "title": item["case_name"],
            "investigator_name": current_user.full_name or "Investigator",
            "priority": "Medium",
            "status": item["case_status"],
            "created_at": item["last_updated"] or datetime.now(timezone.utc)
        })
    return result


def get_report_details(db: Session, case_id: int, current_user: User):
    """Legacy endpoint returning single report details."""
    try:
        return get_report_view_data(db, str(case_id), current_user)
    except Exception:
        return None


def search_reports(db: Session, keyword: str, current_user: User):
    """Legacy search endpoint."""
    table_data = get_investigator_reports_table(
        db=db,
        current_user=current_user,
        keyword=keyword,
        page=1,
        page_size=50
    )
    return table_data["items"]