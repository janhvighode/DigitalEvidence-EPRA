from datetime import datetime, timezone
from typing import List, Dict, Any, Optional
from sqlalchemy.orm import Session
from sqlalchemy import or_
from fastapi import HTTPException, status

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.possible_entity import PossibleEntity
from models.case_timeline import CaseTimeline
from models.case_note import CaseNote

from services.evidence_service import authorize_case_access, get_case_or_404
from services.epra_service import normalize_epra_evidence_type, CANONICAL_EPRA_TYPES
from services.timeline_service import TimelineService
from services.suspect_ranking_service import get_case_ranked_possible_entities


# ============================================================
# SECTION 1: BASIC INFORMATION
# ============================================================

def get_case_basic_information(db: Session, case: Case) -> Dict[str, Any]:
    """
    Extracts strictly database-backed basic information for a case.
    Dynamic joins resolve the creator (assigned_by), investigator, and cyber expert.
    """
    creator = db.query(User).filter(User.id == case.created_by).first() if case.created_by else None
    investigator = db.query(User).filter(User.id == case.investigator_id).first() if case.investigator_id else None
    cyber_expert = db.query(User).filter(User.id == case.cyber_expert_id).first() if case.cyber_expert_id else None

    # Crime type is dynamically derived from description or standardized general type
    crime_type = case.description if (case.description and len(case.description.strip()) > 0) else "General Cyber Crime"

    return {
        "id": case.id,
        "case_id": case.case_id,
        "case_name": case.title,
        "crime_type": crime_type,
        "priority": case.priority,
        "status": case.status,
        "assigned_date": case.created_at,
        "assigned_by": creator.full_name if creator else "Administrator",
        "description": case.description or "",
        "investigator_id": case.investigator_id,
        "investigator_name": investigator.full_name if investigator else None,
        "cyber_expert_id": case.cyber_expert_id,
        "cyber_expert_name": cyber_expert.full_name if cyber_expert else None,
        "created_at": case.created_at,
        "updated_at": case.updated_at
    }


# ============================================================
# SECTION 2: INVOLVED ENTITIES
# ============================================================

def get_case_involved_entities(
    db: Session,
    case: Case,
    current_user: User
) -> List[Dict[str, Any]]:
    """
    Reuses existing suspect ranking and possible entities services.
    Returns genuine persisted entities or an empty list. Never invents fake entities.
    """
    try:
        entities = get_case_ranked_possible_entities(db, case, current_user=current_user)
        return entities
    except Exception:
        # Fallback to direct relational query if suspect ranking service encounters any edge case
        db_entities = (
            db.query(PossibleEntity)
            .filter(PossibleEntity.case_id == case.id)
            .order_by(PossibleEntity.rank.asc())
            .all()
        )
        results = []
        for pe in db_entities:
            results.append({
                "id": pe.id,
                "suspect_id": pe.suspect_id,
                "suspect_name": pe.suspect_name,
                "entity_type": pe.entity_type,
                "rank": pe.rank,
                "total_epra_score": pe.total_epra_score,
                "linked_evidence_count": pe.linked_evidence_count,
                "linked_evidence_ids": [link.evidence.evidence_id for link in pe.evidence_links if link.evidence],
                "confidence_score": pe.confidence_score,
                "created_at": pe.created_at,
                "processed_at": pe.processed_at
            })
        return results


# ============================================================
# SECTION 3: CASE TIMELINE OVERVIEW
# ============================================================

def get_case_timeline_overview(db: Session, case: Case) -> List[Dict[str, Any]]:
    """
    Authoritative timeline aggregator.
    Reuses TimelineService.build_case_timeline (deduplicated CustodyLog + ActivityLog)
    and merges with case_timeline records.
    Guarantees true occurrence timestamps and no synthetic/fake events.
    """
    timeline_items: List[Dict[str, Any]] = []
    seen_keys = set()

    # Source 1: case_timeline entries
    case_timeline_entries = (
        db.query(CaseTimeline)
        .filter(CaseTimeline.case_id == case.id)
        .order_by(CaseTimeline.created_at.desc())
        .all()
    )

    actor_ids = {ct.performed_by for ct in case_timeline_entries if ct.performed_by}
    user_map = {}
    if actor_ids:
        users = db.query(User).filter(User.id.in_(actor_ids)).all()
        user_map = {u.id: u.full_name or u.username for u in users}

    for ct in case_timeline_entries:
        actor_name = user_map.get(ct.performed_by)
        ts_str = ct.created_at.isoformat() if ct.created_at else None
        key = (ct.event, ts_str)
        if key not in seen_keys:
            seen_keys.add(key)
            timeline_items.append({
                "event_id": f"ct_{ct.id}",
                "case_id": str(case.case_id),
                "event_type": "CASE_TIMELINE_EVENT",
                "title": ct.event,
                "description": ct.event,
                "timestamp": ts_str,
                "actor": actor_name,
                "actor_role": ct.performed_by_role,
                "source": "CASE_TIMELINE",
                "status": "COMPLETED",
                "_sort_dt": ct.created_at
            })

    # Source 2: TimelineService (CustodyLog + ActivityLog with event_reference deduplication)
    try:
        audit_events = TimelineService.build_case_timeline(db, str(case.case_id))
        for ae in audit_events:
            ts_str = ae.get("timestamp")
            dt = None
            if ts_str:
                try:
                    dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                except Exception:
                    dt = None

            desc = ae.get("description") or ae.get("event_type")
            key = (desc, ts_str)
            if key not in seen_keys:
                seen_keys.add(key)
                timeline_items.append({
                    "event_id": f"audit_{ae.get('step', ae.get('sort_id'))}",
                    "case_id": str(case.case_id),
                    "event_type": ae.get("event_type", "AUDIT_EVENT"),
                    "title": ae.get("event_type", "Audit Event"),
                    "description": desc,
                    "timestamp": ts_str,
                    "actor": ae.get("actor"),
                    "actor_role": None,
                    "source": ae.get("source", "AUDIT_TRAIL"),
                    "status": "COMPLETED",
                    "_sort_dt": dt
                })
    except Exception:
        pass

    # Baseline event if no timeline records exist yet
    if not timeline_items:
        creator = db.query(User).filter(User.id == case.created_by).first() if case.created_by else None
        ts_str = case.created_at.isoformat() if case.created_at else None
        timeline_items.append({
            "event_id": f"created_{case.id}",
            "case_id": str(case.case_id),
            "event_type": "CASE_CREATED",
            "title": "Case Created",
            "description": f"Case created: {case.title} ({case.case_id})",
            "timestamp": ts_str,
            "actor": creator.full_name if creator else "System",
            "actor_role": "Administrator",
            "source": "DATABASE",
            "status": "COMPLETED",
            "_sort_dt": case.created_at
        })

    # Sort descending by occurrence timestamp
    def sort_key(item):
        dt = item.get("_sort_dt")
        if dt:
            if hasattr(dt, "timestamp"):
                return dt.timestamp()
        return 0

    timeline_items.sort(key=sort_key, reverse=True)

    # Clean up internal sorting helper
    for item in timeline_items:
        item.pop("_sort_dt", None)

    return timeline_items


# ============================================================
# SECTION 4: EVIDENCE SUMMARY
# ============================================================

def get_case_evidence_summary(db: Session, case: Case) -> Dict[str, Any]:
    """
    Computes genuine evidence metrics for the case using the central EPRA
    canonical type normalizer.
    All 12 canonical types are supported:
    IMAGE, VIDEO, AUDIO, DOCUMENT, PDF, SPREADSHEET, EMAIL, EXECUTABLE, DATABASE, LOG, ARCHIVE, UNKNOWN.
    Summary categories dynamically aggregate without destroying canonical types:
    - Images: IMAGE
    - Documents: DOCUMENT + PDF + SPREADSHEET + EMAIL + LOG
    - Videos: VIDEO
    - Audio: AUDIO
    - Others: EXECUTABLE + DATABASE + ARCHIVE + UNKNOWN
    """
    evidence_records = (
        db.query(Evidence)
        .filter(Evidence.case_id == case.id)
        .all()
    )

    total_evidence = len(evidence_records)

    # Initialize all 12 canonical types
    counts_by_type = {ctype: 0 for ctype in sorted(CANONICAL_EPRA_TYPES)}

    for ev in evidence_records:
        ctype = normalize_epra_evidence_type(ev.file_name, ev.file_type)
        if ctype not in counts_by_type:
            ctype = "UNKNOWN"
        counts_by_type[ctype] += 1

    # Derived summary categories
    images_count = counts_by_type.get("IMAGE", 0)
    videos_count = counts_by_type.get("VIDEO", 0)
    audio_count = counts_by_type.get("AUDIO", 0)

    documents_count = (
        counts_by_type.get("DOCUMENT", 0) +
        counts_by_type.get("PDF", 0) +
        counts_by_type.get("SPREADSHEET", 0) +
        counts_by_type.get("EMAIL", 0) +
        counts_by_type.get("LOG", 0)
    )

    others_count = (
        counts_by_type.get("EXECUTABLE", 0) +
        counts_by_type.get("DATABASE", 0) +
        counts_by_type.get("ARCHIVE", 0) +
        counts_by_type.get("UNKNOWN", 0)
    )

    return {
        "total_evidence": total_evidence,
        "counts_by_type": counts_by_type,
        "summary_categories": {
            "images": images_count,
            "documents": documents_count,
            "videos": videos_count,
            "audio": audio_count,
            "others": others_count
        }
    }


# ============================================================
# SECTION 6: CASE NOTES
# ============================================================

def get_case_notes(db: Session, case: Case) -> List[Dict[str, Any]]:
    """
    Retrieves all persistent case notes for the selected case.
    Strictly case-isolated and joined with users table to provide author name.
    """
    notes = (
        db.query(CaseNote, User.full_name, User.username)
        .join(User, CaseNote.created_by == User.id)
        .filter(CaseNote.case_id == case.id)
        .order_by(CaseNote.created_at.desc())
        .all()
    )

    results = []
    for note, full_name, username in notes:
        results.append({
            "id": note.id,
            "case_id": note.case_id,
            "content": note.content,
            "created_by": note.created_by,
            "created_by_name": full_name or username or f"User #{note.created_by}",
            "created_at": note.created_at,
            "updated_at": note.updated_at
        })

    return results


def create_case_note(
    db: Session,
    case: Case,
    content: str,
    current_user: User
) -> Dict[str, Any]:
    """
    Persists a new note for the case.
    - Author is strictly derived from authenticated current_user.id.
    - Rejects empty or whitespace-only content with 400 Bad Request.
    - Appends an audit event to case_timeline.
    """
    cleaned_content = (content or "").strip()
    if not cleaned_content:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Note content cannot be blank or empty"
        )

    new_note = CaseNote(
        case_id=case.id,
        content=cleaned_content,
        created_by=current_user.id
    )
    db.add(new_note)
    db.commit()
    db.refresh(new_note)

    # Record event in CaseTimeline
    try:
        user_role = (
            "Cyber Expert" if current_user.role_id == 3
            else ("Investigator" if current_user.role_id == 2 else "Administrator")
        )
        timeline_entry = CaseTimeline(
            case_id=case.id,
            event=f"Case note added by {current_user.full_name or current_user.username}",
            performed_by=current_user.id,
            performed_by_role=user_role
        )
        db.add(timeline_entry)
        db.commit()
    except Exception:
        db.rollback()

    return {
        "id": new_note.id,
        "case_id": new_note.case_id,
        "content": new_note.content,
        "created_by": new_note.created_by,
        "created_by_name": current_user.full_name or current_user.username,
        "created_at": new_note.created_at,
        "updated_at": new_note.updated_at
    }


# ============================================================
# PAGE-LEVEL AGGREGATOR
# ============================================================

def get_aggregated_case_details(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> Dict[str, Any]:
    """
    Aggregates all 5 sections for the Case Details page into a single response.
    Enforces strict role-based and assigned-case authorization.
    Reuses existing underlying services without reimplementing logic.
    """
    case = authorize_case_access(db, case_identifier, current_user)

    basic_info = get_case_basic_information(db, case)
    entities = get_case_involved_entities(db, case, current_user)
    timeline = get_case_timeline_overview(db, case)
    evidence_summary = get_case_evidence_summary(db, case)
    notes = get_case_notes(db, case)

    return {
        "basic_information": basic_info,
        "involved_entities": entities,
        "timeline": timeline,
        "evidence_summary": evidence_summary,
        "case_notes": notes
    }
