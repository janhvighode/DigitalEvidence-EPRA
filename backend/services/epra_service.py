import sys
from pathlib import Path
from typing import Any, Dict, List, Optional
from datetime import datetime

# Ensure project root is in sys.path so ai_modules is importable in all environments
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import or_

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.epra_result import EPRAResult
from services.timeline_service import create_timeline_event

# Import Janhvi's EPRA v2 engine directly without altering methodology
from ai_modules.epra_v2.models.evidence import Evidence as JanhviEvidence
from ai_modules.epra_v2.models.metadata import Metadata as JanhviMetadata
from ai_modules.epra_v2.services.epra_service import EPRAService
from ai_modules.epra_v2.ranking.evidence_ranker import EvidenceRanker
from ai_modules.epra_v2.intelligence.evidence_classifier import EvidenceClassifier


def get_case_or_404(db: Session, case_identifier: str | int) -> Case:
    """
    Resolves a case seamlessly by either database integer PK (Case.id)
    or human-readable case string (Case.case_id).
    """
    ident_str = str(case_identifier).strip()

    if ident_str.isdigit():
        case = db.query(Case).filter(
            or_(
                Case.id == int(ident_str),
                Case.case_id == ident_str
            )
        ).first()
    else:
        case = db.query(Case).filter(
            Case.case_id.ilike(ident_str)
        ).first()

    if not case:
        raise HTTPException(
            status_code=404,
            detail=f"Case '{case_identifier}' not found"
        )

    return case


def authorize_cyber_expert_case_access(
    db: Session,
    case_identifier: str | int,
    current_user: User
) -> Case:
    """
    Enforces strict Cyber Expert security:
    - Authenticated user must have role_id == 3 (Cyber Expert)
    - Case must be assigned to this Cyber Expert (Case.cyber_expert_id == current_user.id)
    """
    if current_user.role_id != 3:
        raise HTTPException(
            status_code=403,
            detail="Cyber Expert access required"
        )

    case = get_case_or_404(db, case_identifier)

    if case.cyber_expert_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail="Access denied: You are not assigned as Cyber Expert to this case"
        )

    return case


def process_case_epra(
    db: Session,
    case: Case,
    current_user: User,
    external_inputs: Optional[Dict[str, Dict[str, Any]]] = None,
    demo_mode: bool = False
) -> Dict[str, Any]:
    """
    Runs Janhvi's EPRA analysis on all evidence items belonging to the case:
    1. Loads real evidence and Member 5 SHA-256 integrity records from DB.
    2. Maps DB records into Janhvi's Evidence/Metadata dataclasses.
    3. Handles Member 3 CBIR/Semantic contract:
       - For IMAGE: Missing semantic_score -> SI=null, semantic_status='PENDING'.
       - For IMAGE: Real measured score (including 0.0000) -> SI=0.0000, semantic_status='MEASURED'.
       - For Non-IMAGE: Evaluates content against case context via TF-IDF.
    4. Executes EPRAService.process on each evidence item.
    5. Executes EvidenceRanker.rank on the case collection.
    6. Persists/upserts results into epra_results table.
    7. Records case timeline event.
    8. Returns execution summary and ranked evidence.
    """
    evidence_records = (
        db.query(Evidence)
        .filter(Evidence.case_id == case.id)
        .order_by(Evidence.id.asc())
        .all()
    )

    if not evidence_records:
        return {
            "message": "No evidence records found for this case",
            "case_id": case.case_id,
            "total_processed": 0,
            "summary": {
                "case_id": case.case_id,
                "total_evidence": 0,
                "critical": 0,
                "high": 0,
                "medium": 0,
                "low": 0,
                "very_low": 0,
                "pending_analysis": 0,
                "score_distribution": {
                    "critical": 0, "high": 0, "medium": 0, "low": 0, "very_low": 0, "pending": 0
                },
                "average_epra_score": 0.0,
                "top_evidence": [],
                "last_processed_at": datetime.now()
            },
            "ranked_evidence": []
        }

    case_context = {
        "description": case.description or case.title or "",
        "keywords": [case.title or ""]
    }

    processed_janhvi_list: List[JanhviEvidence] = []
    evidence_meta_map: Dict[str, Dict[str, Any]] = {}

    for ev in evidence_records:
        # Load associated Member 5 integrity record
        h_rec = (
            db.query(EvidenceHash)
            .filter(EvidenceHash.evidence_id == ev.id)
            .first()
        )

        ext = Path(ev.file_name).suffix.lower()
        meta = JanhviMetadata(
            file_name=ev.file_name,
            extension=ext,
            mime_type="application/octet-stream",
            size=ev.file_size or 0,
            absolute_path=ev.file_path or "",
            parent_directory=str(Path(ev.file_path).parent) if ev.file_path else "",
            created_time=ev.created_at,
            case_id=str(case.case_id),
            evidence_id=str(ev.evidence_id),
            evidence_type=ev.file_type
        )

        j_ev = JanhviEvidence(metadata=meta)
        j_ev = EvidenceClassifier.process(j_ev)

        # Connect Member 5 SHA-256 integrity facts
        if h_rec:
            j_ev.stored_hash = h_rec.original_hash or ""
            j_ev.generated_hash = h_rec.current_hash or ""
            j_ev.hash_verified = bool(h_rec.hash_match)
            if h_rec.tampered:
                j_ev.integrity_risk = 1.0

        # Check for external inputs
        ev_inputs = {}
        if external_inputs:
            ev_inputs = (
                external_inputs.get(ev.evidence_id)
                or external_inputs.get(str(ev.id))
                or external_inputs.get(ev.file_name)
                or {}
            )

        evidence_type = j_ev.metadata.evidence_type
        is_image = (evidence_type == "IMAGE")
        image_semantic_supplied = False
        image_semantic_score = None

        if is_image:
            if "semantic_score" in ev_inputs and ev_inputs["semantic_score"] is not None:
                image_semantic_score = float(ev_inputs["semantic_score"])
                image_semantic_supplied = True
                # Set on evidence object for Janhvi's engine
                j_ev.semantic_score = image_semantic_score
            else:
                j_ev.semantic_score = 0.0

        # Ingest Behaviour / Relationship inputs if provided
        if "access_frequency" in ev_inputs:
            j_ev.access_frequency = float(ev_inputs["access_frequency"])
        if "repetition_factor" in ev_inputs:
            j_ev.repetition_factor = float(ev_inputs["repetition_factor"])
        if "deletion_factor" in ev_inputs:
            j_ev.deletion_factor = float(ev_inputs["deletion_factor"])
        if "privilege_factor" in ev_inputs:
            j_ev.privilege_factor = float(ev_inputs["privilege_factor"])
        if "related_entities" in ev_inputs:
            j_ev.related_entities = ev_inputs["related_entities"]

        # Run Janhvi's EPRA engine
        processed = EPRAService.process(
            evidence=j_ev,
            evidence_database=processed_janhvi_list,
            demo_mode=demo_mode,
            case_context=case_context
        )
        processed_janhvi_list.append(processed)

        # Store forensic & pending status mapping
        evidence_meta_map[ev.evidence_id] = {
            "db_evidence": ev,
            "hash_rec": h_rec,
            "is_image": is_image,
            "image_semantic_supplied": image_semantic_supplied,
            "image_semantic_score": image_semantic_score
        }

    # Rank all evidence in the case collection using Janhvi's EvidenceRanker
    ranked_janhvi_list = EvidenceRanker.rank(processed_janhvi_list)

    now = datetime.now()
    ranked_responses = []

    for rank_idx, j_ev in enumerate(ranked_janhvi_list, start=1):
        ev_id_str = j_ev.metadata.evidence_id
        meta_info = evidence_meta_map[ev_id_str]
        ev = meta_info["db_evidence"]
        h_rec = meta_info["hash_rec"]
        is_image = meta_info["is_image"]
        image_semantic_supplied = meta_info["image_semantic_supplied"]
        image_semantic_score = meta_info["image_semantic_score"]

        # -------------------------------------------------------------
        # SEMANTIC INTELLIGENCE & PENDING INPUT RESOLUTION
        # -------------------------------------------------------------
        if is_image:
            if not image_semantic_supplied:
                # Critical Rule 9: Missing IMAGE score -> null & PENDING
                si_val = None
                semantic_status = "PENDING"
                pending_inputs = ["Awaiting IMAGE CBIR/Semantic score"]
                analysis_status = "PARTIAL / PENDING INPUTS"
            else:
                # Real calculated semantic value (including 0.0000) -> MEASURED
                si_val = round(float(image_semantic_score), 4)
                semantic_status = "MEASURED"
                pending_inputs = []
                analysis_status = "COMPLETE"
        else:
            # Non-image evidence
            if hasattr(j_ev, "pending_external_inputs") and "SI" in j_ev.pending_external_inputs:
                si_val = None
                semantic_status = "PENDING"
                pending_inputs = ["Awaiting document content for semantic analysis"]
                analysis_status = "PARTIAL / PENDING INPUTS"
            else:
                si_val = round(float(j_ev.semantic_intelligence), 4)
                semantic_status = "MEASURED"
                pending_inputs = []
                analysis_status = "COMPLETE"

        # Check if other factors have pending reasons
        if hasattr(j_ev, "pending_external_inputs") and j_ev.pending_external_inputs:
            for k, msg in j_ev.pending_external_inputs.items():
                if k != "SI" and msg not in pending_inputs:
                    pending_inputs.append(msg)
            if pending_inputs and analysis_status == "COMPLETE":
                analysis_status = "PARTIAL / PENDING INPUTS"

        # -------------------------------------------------------------
        # DATABASE PERSISTENCE (UPSERT)
        # -------------------------------------------------------------
        epra_record = (
            db.query(EPRAResult)
            .filter(
                EPRAResult.case_id == case.id,
                EPRAResult.evidence_id == ev.id
            )
            .first()
        )

        if not epra_record:
            epra_record = EPRAResult(
                case_id=case.id,
                evidence_id=ev.id
            )
            db.add(epra_record)

        epra_record.authenticity_risk = j_ev.authenticity_risk
        epra_record.context_intelligence = j_ev.context_intelligence
        epra_record.behaviour_intelligence = j_ev.behaviour_intelligence
        epra_record.semantic_intelligence = si_val
        epra_record.investigative_intelligence = j_ev.investigative_intelligence
        epra_record.semantic_status = semantic_status

        epra_record.ipi = j_ev.investigation_priority_index
        epra_record.epra_score = j_ev.epra_score
        epra_record.priority = j_ev.priority
        epra_record.rank = rank_idx

        epra_record.hash_verified = j_ev.hash_verified
        epra_record.is_duplicate = j_ev.is_duplicate
        epra_record.analysis_status = analysis_status
        epra_record.pending_external_inputs = pending_inputs
        epra_record.processed_at = now

        ranked_responses.append({
            "rank": rank_idx,
            "evidence_id": ev.evidence_id,
            "file_name": ev.file_name,
            "evidence_type": j_ev.metadata.evidence_type,
            "file_size": ev.file_size,
            "authenticity_risk": j_ev.authenticity_risk,
            "context_intelligence": j_ev.context_intelligence,
            "behaviour_intelligence": j_ev.behaviour_intelligence,
            "semantic_intelligence": si_val,
            "investigative_intelligence": j_ev.investigative_intelligence,
            "ipi": j_ev.investigation_priority_index,
            "epra_score": j_ev.epra_score,
            "priority": j_ev.priority,
            "semantic_status": semantic_status,
            "analysis_status": analysis_status,
            "hash_verified": j_ev.hash_verified,
            "duplicate": j_ev.is_duplicate,
            "pending_external_inputs": pending_inputs,
            "processed_at": now
        })

    db.commit()

    # Record timeline event
    create_timeline_event(
        db=db,
        case_id=case.id,
        event=f"EPRA Analysis executed: {len(ranked_responses)} evidence items prioritized",
        performed_by=current_user.id,
        performed_by_role="Cyber Expert"
    )

    summary = calculate_summary_metrics(
        case=case,
        total_evidence_count=len(evidence_records),
        results=ranked_responses,
        last_processed_at=now
    )

    return {
        "message": "EPRA analysis executed and prioritized results stored successfully",
        "case_id": case.case_id,
        "total_processed": len(ranked_responses),
        "summary": summary,
        "ranked_evidence": ranked_responses
    }


def calculate_summary_metrics(
    case: Case,
    total_evidence_count: int,
    results: List[Dict[str, Any]],
    last_processed_at: Optional[datetime] = None
) -> Dict[str, Any]:
    """
    Computes summary metrics dynamically from the actual EPRA result set.
    Ensures mathematical consistency:
    total_evidence = critical + high + medium + low + very_low + pending_analysis
    """
    critical_count = sum(1 for r in results if (r.get("priority") or "").upper() == "CRITICAL")
    high_count = sum(1 for r in results if (r.get("priority") or "").upper() == "HIGH")
    medium_count = sum(1 for r in results if (r.get("priority") or "").upper() == "MEDIUM")
    low_count = sum(1 for r in results if (r.get("priority") or "").upper() == "LOW")
    very_low_count = sum(1 for r in results if (r.get("priority") or "").upper() == "VERY LOW")

    analyzed_count = len(results)
    pending_analysis = max(0, total_evidence_count - analyzed_count)

    scores = [r["epra_score"] for r in results if r.get("epra_score") is not None]
    avg_score = round(sum(scores) / len(scores), 2) if scores else 0.0

    # Top 5 records from the same ranked results
    sorted_results = sorted(
        results,
        key=lambda x: (x.get("rank") or 9999, -(x.get("epra_score") or 0.0))
    )
    top_5 = sorted_results[:5]

    return {
        "case_id": case.case_id,
        "total_evidence": total_evidence_count,
        "critical": critical_count,
        "high": high_count,
        "medium": medium_count,
        "low": low_count,
        "very_low": very_low_count,
        "pending_analysis": pending_analysis,
        "score_distribution": {
            "critical": critical_count,
            "high": high_count,
            "medium": medium_count,
            "low": low_count,
            "very_low": very_low_count,
            "pending": pending_analysis
        },
        "average_epra_score": avg_score,
        "top_evidence": top_5,
        "last_processed_at": last_processed_at
    }


def get_case_epra_summary(db: Session, case: Case) -> Dict[str, Any]:
    """
    Retrieves the stored EPRA summary for the case.
    Derives all counts and top evidence dynamically from stored DB records.
    """
    total_evidence = (
        db.query(Evidence)
        .filter(Evidence.case_id == case.id)
        .count()
    )

    records = (
        db.query(EPRAResult, Evidence)
        .join(Evidence, EPRAResult.evidence_id == Evidence.id)
        .filter(EPRAResult.case_id == case.id)
        .order_by(EPRAResult.rank.asc(), EPRAResult.epra_score.desc())
        .all()
    )

    results = []
    latest_processed_at = None

    for epra, ev in records:
        if epra.processed_at:
            if latest_processed_at is None or epra.processed_at > latest_processed_at:
                latest_processed_at = epra.processed_at

        results.append({
            "rank": epra.rank or 0,
            "evidence_id": ev.evidence_id,
            "file_name": ev.file_name,
            "evidence_type": ev.file_type,
            "file_size": ev.file_size,
            "authenticity_risk": epra.authenticity_risk,
            "context_intelligence": epra.context_intelligence,
            "behaviour_intelligence": epra.behaviour_intelligence,
            "semantic_intelligence": epra.semantic_intelligence,
            "investigative_intelligence": epra.investigative_intelligence,
            "ipi": epra.ipi,
            "epra_score": epra.epra_score,
            "priority": epra.priority,
            "semantic_status": epra.semantic_status,
            "analysis_status": epra.analysis_status,
            "hash_verified": epra.hash_verified,
            "duplicate": epra.is_duplicate,
            "pending_external_inputs": epra.pending_external_inputs or [],
            "processed_at": epra.processed_at
        })

    return calculate_summary_metrics(
        case=case,
        total_evidence_count=total_evidence,
        results=results,
        last_processed_at=latest_processed_at
    )


def get_case_ranked_evidence(
    db: Session,
    case: Case,
    limit: Optional[int] = None,
    priority: Optional[str] = None
) -> List[Dict[str, Any]]:
    """
    Returns stored ranked evidence items for the case, ordered strictly by EPRA rank.
    Supports optional priority filtering and limit for top N evidence.
    """
    query = (
        db.query(EPRAResult, Evidence)
        .join(Evidence, EPRAResult.evidence_id == Evidence.id)
        .filter(EPRAResult.case_id == case.id)
    )

    if priority:
        query = query.filter(EPRAResult.priority.ilike(priority.strip()))

    query = query.order_by(EPRAResult.rank.asc(), EPRAResult.epra_score.desc())

    if limit and limit > 0:
        query = query.limit(limit)

    records = query.all()

    results = []
    for epra, ev in records:
        results.append({
            "rank": epra.rank or 0,
            "evidence_id": ev.evidence_id,
            "file_name": ev.file_name,
            "evidence_type": ev.file_type,
            "file_size": ev.file_size,
            "authenticity_risk": epra.authenticity_risk,
            "context_intelligence": epra.context_intelligence,
            "behaviour_intelligence": epra.behaviour_intelligence,
            "semantic_intelligence": epra.semantic_intelligence,
            "investigative_intelligence": epra.investigative_intelligence,
            "ipi": epra.ipi,
            "epra_score": epra.epra_score,
            "priority": epra.priority,
            "semantic_status": epra.semantic_status,
            "analysis_status": epra.analysis_status,
            "hash_verified": epra.hash_verified,
            "duplicate": epra.is_duplicate,
            "pending_external_inputs": epra.pending_external_inputs or [],
            "processed_at": epra.processed_at
        })

    return results


def get_evidence_epra_detail(
    db: Session,
    case: Case,
    evidence_identifier: str | int
) -> Dict[str, Any]:
    """
    Returns detailed forensic and EPRA scores for a single evidence item,
    ensuring it belongs strictly to the authorized parent case.
    """
    ident_str = str(evidence_identifier).strip()

    if ident_str.isdigit():
        evidence = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            or_(
                Evidence.id == int(ident_str),
                Evidence.evidence_id == ident_str
            )
        ).first()
    else:
        evidence = db.query(Evidence).filter(
            Evidence.case_id == case.id,
            Evidence.evidence_id.ilike(ident_str)
        ).first()

    if not evidence:
        raise HTTPException(
            status_code=404,
            detail=f"Evidence '{evidence_identifier}' not found for this case"
        )

    epra = (
        db.query(EPRAResult)
        .filter(
            EPRAResult.case_id == case.id,
            EPRAResult.evidence_id == evidence.id
        )
        .first()
    )

    if not epra:
        raise HTTPException(
            status_code=404,
            detail=f"EPRA analysis has not yet been processed for evidence '{evidence_identifier}'"
        )

    h = (
        db.query(EvidenceHash)
        .filter(EvidenceHash.evidence_id == evidence.id)
        .first()
    )

    hash_details = None
    if h:
        hash_details = {
            "current_hash": h.current_hash,
            "original_hash": h.original_hash,
            "hash_match": h.hash_match,
            "tampered": h.tampered,
            "integrity_status": h.integrity_status,
            "verified_at": h.verified_at
        }

    return {
        "evidence_id": evidence.evidence_id,
        "file_name": evidence.file_name,
        "evidence_type": evidence.file_type,
        "file_size": evidence.file_size,
        "file_path": evidence.file_path,
        "hash_verified": epra.hash_verified,
        "duplicate": epra.is_duplicate,
        "original_evidence_id": None,
        "authenticity_risk": epra.authenticity_risk,
        "context_intelligence": epra.context_intelligence,
        "behaviour_intelligence": epra.behaviour_intelligence,
        "semantic_intelligence": epra.semantic_intelligence,
        "investigative_intelligence": epra.investigative_intelligence,
        "ipi": epra.ipi,
        "epra_score": epra.epra_score,
        "priority": epra.priority,
        "rank": epra.rank,
        "semantic_status": epra.semantic_status,
        "analysis_status": epra.analysis_status,
        "pending_external_inputs": epra.pending_external_inputs or [],
        "hash_details": hash_details,
        "processed_at": epra.processed_at
    }
