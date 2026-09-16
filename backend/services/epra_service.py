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
from models.evidence_record import EvidenceRecord
from models.epra_result import EPRAResult
from models.cbir_result import CBIRResult
from services.timeline_service import create_timeline_event
from services.notification_service import create_notification

# Import Janhvi's EPRA v2 engine directly without altering methodology
from ai_modules.epra_v2.models.evidence import Evidence as JanhviEvidence
from ai_modules.epra_v2.models.metadata import Metadata as JanhviMetadata
from ai_modules.epra_v2.services.epra_service import EPRAService
from ai_modules.epra_v2.ranking.evidence_ranker import EvidenceRanker
from ai_modules.epra_v2.intelligence.evidence_classifier import EvidenceClassifier


CANONICAL_EPRA_TYPES = {
    "IMAGE", "VIDEO", "AUDIO", "EMAIL", "PDF", "DOCUMENT",
    "SPREADSHEET", "EXECUTABLE", "DATABASE", "LOG", "ARCHIVE", "UNKNOWN"
}


def normalize_epra_evidence_type(
    filename: Optional[str] = None,
    mime_type: Optional[str] = None,
    raw_type: Optional[str] = None
) -> str:
    """
    Central Canonical EPRA evidence type normalizer.
    Maps raw MIME types, categories, or filenames strictly to one of the 12 canonical types:
    IMAGE, VIDEO, AUDIO, EMAIL, PDF, DOCUMENT, SPREADSHEET, EXECUTABLE, DATABASE, LOG, ARCHIVE, UNKNOWN.
    Accepts arguments positionally or via keywords.
    """
    candidates = [c for c in (raw_type, mime_type, filename) if c]

    # 1. Direct match with canonical types
    for cand in candidates:
        cand_str = str(cand).strip().upper()
        if cand_str in CANONICAL_EPRA_TYPES:
            return cand_str

    # 2. Match from MIME types or types containing '/'
    for cand in candidates:
        m = str(cand).strip().lower()
        if "/" in m:
            if m.startswith("image/"):
                return "IMAGE"
            if m.startswith("video/"):
                return "VIDEO"
            if m.startswith("audio/"):
                return "AUDIO"
            if m == "application/pdf":
                return "PDF"
            if m in ("message/rfc822", "application/vnd.ms-outlook", "application/eml"):
                return "EMAIL"
            if m in ("application/x-msdos-program", "application/x-executable", "application/x-msdownload", "application/x-bat"):
                return "EXECUTABLE"
            if m in ("text/csv", "application/vnd.ms-excel", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"):
                return "SPREADSHEET"
            if m in ("text/plain", "application/msword", "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/rtf", "text/rtf"):
                return "DOCUMENT"
            if m in ("application/x-sqlite3", "application/vnd.sqlite3", "application/sql", "application/x-msaccess"):
                return "DATABASE"
            if m in ("application/zip", "application/x-tar", "application/x-7z-compressed", "application/x-rar-compressed", "application/gzip", "application/x-bzip2"):
                return "ARCHIVE"
            if "log" in m or m == "text/x-log":
                return "LOG"

    # 3. Match from file extension via EvidenceClassifier
    if filename:
        classified = EvidenceClassifier.classify(str(filename))
        if classified in CANONICAL_EPRA_TYPES and classified != "UNKNOWN":
            return classified

    for cand in candidates:
        if "." in str(cand):
            classified = EvidenceClassifier.classify(str(cand))
            if classified in CANONICAL_EPRA_TYPES and classified != "UNKNOWN":
                return classified

    # 4. Fallback checking substrings across candidates
    for cand in candidates:
        r_low = str(cand).strip().lower()
        if any(w in r_low for w in ("image", "photo", "picture", "jpeg", "jpg", "png", "webp", "bmp")):
            return "IMAGE"
        if "pdf" in r_low:
            return "PDF"
        if "mail" in r_low or "eml" in r_low:
            return "EMAIL"
        if any(w in r_low for w in ("sheet", "csv", "excel", "xls")):
            return "SPREADSHEET"
        if any(w in r_low for w in ("doc", "text", "word", "rtf", "odt")):
            return "DOCUMENT"
        if any(w in r_low for w in ("video", "mp4", "mkv", "avi")):
            return "VIDEO"
        if any(w in r_low for w in ("audio", "sound", "voice", "mp3", "wav")):
            return "AUDIO"
        if any(w in r_low for w in ("exec", "binary", "exe", "dll")):
            return "EXECUTABLE"
        if any(w in r_low for w in ("database", "db", "sql", "sqlite")):
            return "DATABASE"
        if any(w in r_low for w in ("archive", "zip", "tar", "rar", "gz", "7z")):
            return "ARCHIVE"
        if any(w in r_low for w in ("log", "audit", "pcap")):
            return "LOG"

    return "UNKNOWN"


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
    case_identifier: Optional[str | int] = None,
    current_user: Optional[User] = None,
    case_id: Optional[str | int] = None,
    case: Optional[Case | str | int] = None
) -> Case:
    """
    Enforces strict Cyber Expert security:
    - Authenticated user must have role_id == 3 (Cyber Expert)
    - Case must be assigned to this Cyber Expert (Case.cyber_expert_id == current_user.id)
    """
    if current_user is None or current_user.role_id != 3:
        raise HTTPException(
            status_code=403,
            detail="Cyber Expert access required"
        )

    target = case if case is not None else (case_id if case_id is not None else case_identifier)
    if isinstance(target, Case):
        c = target
    else:
        c = get_case_or_404(db, target)

    if c.cyber_expert_id != current_user.id:
        raise HTTPException(
            status_code=403,
            detail="Access denied: You are not assigned as Cyber Expert to this case"
        )

    return c


def authorize_epra_read_case_access(
    db: Session,
    case_identifier: Optional[str | int] = None,
    current_user: Optional[User] = None,
    case_id: Optional[str | int] = None,
    case: Optional[Case | str | int] = None
) -> Case:
    """
    Authorizes read-only access to EPRA outputs:
    - Cyber Expert (role_id == 3): Assigned to this case (Case.cyber_expert_id == current_user.id)
    - Investigator (role_id == 2): Assigned to this case (Case.investigator_id == current_user.id)
    - Prohibits unauthorized roles and cross-case access.
    """
    if not current_user:
        raise HTTPException(
            status_code=401,
            detail="Authentication required"
        )

    target = case if case is not None else (case_id if case_id is not None else case_identifier)
    if isinstance(target, Case):
        c = target
    else:
        c = get_case_or_404(db, target)

    if current_user.role_id == 3:
        if c.cyber_expert_id != current_user.id:
            raise HTTPException(
                status_code=403,
                detail="Access denied: You are not assigned as Cyber Expert to this case"
            )
        return c
    elif current_user.role_id == 2:
        if c.investigator_id != current_user.id:
            raise HTTPException(
                status_code=403,
                detail="Access denied: You are not assigned as Investigator to this case"
            )
        return c
    else:
        raise HTTPException(
            status_code=403,
            detail="Access denied: Only assigned Cyber Experts or Investigators can view EPRA results"
        )


def process_case_epra(
    db: Session,
    case: Optional[Case | str | int] = None,
    current_user: Optional[User] = None,
    external_inputs: Optional[Dict[str, Dict[str, Any]]] = None,
    demo_mode: bool = False,
    case_id: Optional[str | int] = None
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
    target = case if case is not None else case_id
    if target is None:
        raise ValueError("case or case_id must be provided")
    if isinstance(target, Case):
        case = target
    else:
        case = get_case_or_404(db, target)
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
            "status": "SUCCESS",
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
            "ranked_evidence": [],
            "results": []
        }

    case_context = None
    if case.description and case.description.strip():
        case_context = {
            "description": case.description.strip(),
            "keywords": [case.title.strip()] if case.title and case.title.strip() else []
        }
    elif case.title and case.title.strip():
        case_context = {
            "description": case.title.strip(),
            "keywords": [case.title.strip()]
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

        er = (
            db.query(EvidenceRecord)
            .filter(
                (EvidenceRecord.external_evidence_id == ev.evidence_id) |
                (EvidenceRecord.id == ev.id)
            )
            .first()
        )

        ext = Path(ev.file_name).suffix.lower()
        mime_val = getattr(ev, "mime_type", None) or (er.mime_type if er else None)
        canon_type = normalize_epra_evidence_type(
            filename=ev.file_name,
            mime_type=mime_val,
            raw_type=ev.file_type or (er.evidence_type if er else None)
        )

        # Check for external inputs
        ev_inputs = {}
        if external_inputs:
            ev_specific = (
                external_inputs.get(ev.evidence_id)
                or external_inputs.get(str(ev.id))
                or external_inputs.get(ev.file_name)
            )
            if isinstance(ev_specific, dict):
                ev_inputs = ev_specific
            else:
                ev_inputs = external_inputs

        extracted_text_val = (
            ev_inputs.get("extracted_text")
            or ev_inputs.get("content")
            or ev_inputs.get("text")
            or (er.notes if er and er.notes else None)
        )

        meta = JanhviMetadata(
            file_name=ev.file_name,
            extension=ext,
            mime_type=mime_val or "application/octet-stream",
            size=ev.file_size or (er.file_size_bytes if er else 0) or 0,
            absolute_path=ev.file_path or (er.file_path if er else ""),
            parent_directory=str(Path(ev.file_path).parent) if ev.file_path else "",
            created_time=ev.created_at or (er.created_at if er else None),
            case_id=str(case.case_id),
            evidence_id=str(ev.evidence_id),
            evidence_type=canon_type,
            notes=(ev_inputs.get("notes") or (er.notes if er else "") or ""),
            extracted_text=extracted_text_val
        )

        j_ev = JanhviEvidence(metadata=meta)
        j_ev.metadata.evidence_type = canon_type

        # Ingest case context if provided per-evidence or fallback to case context
        ev_context = case_context
        if "context" in ev_inputs and ev_inputs["context"]:
            ctx_str = str(ev_inputs["context"]).strip()
            ev_context = {"description": ctx_str, "keywords": [ctx_str]}

        # Check if non-image has genuine text content
        has_genuine_text = bool(extracted_text_val and str(extracted_text_val).strip())
        if not has_genuine_text and ev.file_path and Path(ev.file_path).is_file():
            try:
                if Path(ev.file_path).stat().st_size > 0:
                    has_genuine_text = True
            except Exception:
                pass

        # Connect Member 5 SHA-256 integrity facts
        if h_rec:
            j_ev.stored_hash = h_rec.original_hash or ""
            j_ev.generated_hash = h_rec.current_hash or ""
            j_ev.hash_verified = bool(h_rec.hash_match)
            if h_rec.tampered:
                j_ev.integrity_risk = 1.0
        elif er:
            j_ev.stored_hash = er.original_sha256 or ""
            j_ev.generated_hash = er.current_sha256 or ""
            j_ev.hash_verified = (er.verification_status == "Verified")
            if er.verification_status == "Tampered":
                j_ev.integrity_risk = 1.0

        is_image = (canon_type == "IMAGE")
        image_semantic_supplied = False
        image_semantic_score = None

        if is_image:
            if "semantic_score" in ev_inputs and ev_inputs["semantic_score"] is not None:
                image_semantic_score = float(ev_inputs["semantic_score"])
                image_semantic_supplied = True
                j_ev.semantic_score = image_semantic_score
            else:
                # Query genuine persisted CBIR comparison result for this case and evidence
                cbir_rec = (
                    db.query(CBIRResult)
                    .filter(
                        CBIRResult.case_id == case.id,
                        or_(
                            CBIRResult.query_evidence_id == ev.id,
                            CBIRResult.candidate_evidence_id == ev.id
                        )
                    )
                    .order_by(CBIRResult.id.desc())
                    .first()
                )
                if cbir_rec and cbir_rec.semantic_score is not None:
                    image_semantic_score = float(cbir_rec.semantic_score)
                    image_semantic_supplied = True
                    j_ev.semantic_score = image_semantic_score
                else:
                    j_ev.semantic_score = None

        # Ingest Behaviour / Relationship inputs if provided
        has_bi_input = False
        bi_explicit_val = None
        if "behavioural_intelligence" in ev_inputs and ev_inputs["behavioural_intelligence"] is not None:
            has_bi_input = True
            bi_explicit_val = float(ev_inputs["behavioural_intelligence"])
        elif "behaviour_intelligence" in ev_inputs and ev_inputs["behaviour_intelligence"] is not None:
            has_bi_input = True
            bi_explicit_val = float(ev_inputs["behaviour_intelligence"])

        if has_bi_input:
            j_ev.access_frequency = bi_explicit_val
            j_ev.repetition_factor = bi_explicit_val
            j_ev.deletion_factor = bi_explicit_val
            j_ev.privilege_factor = bi_explicit_val
            j_ev.behaviour_intelligence = bi_explicit_val

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
        effective_demo_mode = demo_mode
        if not is_image and (not has_genuine_text or not ev_context):
            effective_demo_mode = False
        if is_image and not image_semantic_supplied:
            effective_demo_mode = False

        processed = EPRAService.process(
            evidence=j_ev,
            evidence_database=processed_janhvi_list,
            demo_mode=effective_demo_mode,
            case_context=ev_context
        )
        processed_janhvi_list.append(processed)

        # Store forensic & pending status mapping
        evidence_meta_map[ev.evidence_id] = {
            "db_evidence": ev,
            "hash_rec": h_rec,
            "canon_type": canon_type,
            "is_image": is_image,
            "image_semantic_supplied": image_semantic_supplied,
            "image_semantic_score": image_semantic_score,
            "has_genuine_text": has_genuine_text,
            "has_context": bool(ev_context),
            "has_bi_input": has_bi_input,
            "bi_explicit_val": bi_explicit_val
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
        canon_type = meta_info["canon_type"]
        is_image = meta_info["is_image"]
        image_semantic_supplied = meta_info["image_semantic_supplied"]
        image_semantic_score = meta_info["image_semantic_score"]

        # -------------------------------------------------------------
        # SEMANTIC INTELLIGENCE & PENDING INPUT RESOLUTION
        # -------------------------------------------------------------
        pending_inputs = []
        analysis_status = "COMPLETE"

        if is_image:
            if not image_semantic_supplied:
                si_val = None
                semantic_status = "PENDING"
                pending_inputs.append("Awaiting IMAGE CBIR/Semantic score")
                analysis_status = "PARTIAL / PENDING INPUTS"
            else:
                si_val = round(float(image_semantic_score), 4)
                semantic_status = "MEASURED"
        else:
            # Non-image evidence
            if not meta_info["has_genuine_text"] or not meta_info["has_context"]:
                si_val = None
                semantic_status = "PENDING"
                pending_inputs.append("Awaiting document text content and context for semantic analysis")
                analysis_status = "PARTIAL / PENDING INPUTS"
            elif hasattr(j_ev, "pending_external_inputs") and "SI" in j_ev.pending_external_inputs:
                si_val = None
                semantic_status = "PENDING"
                pending_inputs.append("Awaiting document text content and context for semantic analysis")
                analysis_status = "PARTIAL / PENDING INPUTS"
            else:
                si_val = round(float(j_ev.semantic_intelligence), 4)
                semantic_status = "MEASURED"

        # -------------------------------------------------------------
        # BEHAVIOUR INTELLIGENCE RESOLUTION (Actual zero vs pending)
        # -------------------------------------------------------------
        if meta_info["has_bi_input"]:
            bi_val = round(float(meta_info["bi_explicit_val"]), 4)
            j_ev.behaviour_intelligence = bi_val
        else:
            is_bi_pending = bool(hasattr(j_ev, "pending_external_inputs") and "BI" in j_ev.pending_external_inputs)
            if is_bi_pending:
                bi_val = None
                msg = j_ev.pending_external_inputs["BI"]
                if msg not in pending_inputs:
                    pending_inputs.append(msg)
                analysis_status = "PARTIAL / PENDING INPUTS"
            elif not demo_mode:
                bi_val = None
                pending_inputs.append("Awaiting behavioural audit logs")
                analysis_status = "PARTIAL / PENDING INPUTS"
            else:
                bi_val = round(float(j_ev.behaviour_intelligence), 4)

        # Check if other factors have pending reasons (in production mode)
        if not demo_mode and hasattr(j_ev, "pending_external_inputs") and j_ev.pending_external_inputs:
            for k, msg in j_ev.pending_external_inputs.items():
                if k not in ("SI", "BI") and msg not in pending_inputs:
                    pending_inputs.append(msg)
            if pending_inputs:
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
        epra_record.behaviour_intelligence = bi_val
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
            "evidence_type": canon_type,
            "file_size": ev.file_size,
            "authenticity_risk": j_ev.authenticity_risk,
            "context_intelligence": j_ev.context_intelligence,
            "behaviour_intelligence": bi_val,
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

    # Event-Driven Notifications (Investigator and Cyber Expert)
    has_critical = any(str(r.get("priority", "")).upper() == "CRITICAL" for r in ranked_responses)
    epra_recipients = [uid for uid in [case.investigator_id, case.cyber_expert_id] if uid]

    for rec_id in epra_recipients:
        create_notification(
            db=db,
            title="EPRA Analysis Completed",
            message=f"EPRA prioritization completed for case {case.case_id} ({len(ranked_responses)} items prioritized).",
            notification_type="EPRA_COMPLETE",
            user_id=rec_id,
            cyber_cell_id=None
        )
        if has_critical:
            create_notification(
                db=db,
                title="Critical Evidence Detected",
                message=f"Critical priority evidence identified in case {case.case_id} during EPRA analysis.",
                notification_type="EPRA_CRITICAL_ALERT",
                user_id=rec_id,
                cyber_cell_id=None
            )

    summary = calculate_summary_metrics(
        case=case,
        total_evidence_count=len(evidence_records),
        results=ranked_responses,
        last_processed_at=now
    )

    return {
        "status": "SUCCESS",
        "message": "EPRA analysis executed and prioritized results stored successfully",
        "case_id": case.case_id,
        "total_processed": len(ranked_responses),
        "summary": summary,
        "ranked_evidence": ranked_responses,
        "results": ranked_responses
    }


def calculate_summary_metrics(
    case: Optional[Case] = None,
    total_evidence_count: int = 0,
    results: Optional[List[Dict[str, Any]]] = None,
    last_processed_at: Optional[datetime] = None
) -> Dict[str, Any]:
    """
    Computes summary metrics dynamically from the actual EPRA result set.
    Ensures mathematical consistency:
    total_evidence = critical + high + medium + low + very_low + pending_analysis
    """
    if results is None:
        results = []

    critical_count = sum(1 for r in results if (r.get("priority") or "").upper() == "CRITICAL")
    high_count = sum(1 for r in results if (r.get("priority") or "").upper() == "HIGH")
    medium_count = sum(1 for r in results if (r.get("priority") or "").upper() == "MEDIUM")
    low_count = sum(1 for r in results if (r.get("priority") or "").upper() == "LOW")
    very_low_count = sum(1 for r in results if (r.get("priority") or "").upper() in ("VERY LOW", "VERY_LOW"))

    analyzed_count = len(results)
    completed_analysis = sum(1 for r in results if r.get("analysis_status") == "COMPLETE")
    partial_analysis = sum(1 for r in results if r.get("analysis_status") == "PARTIAL / PENDING INPUTS")
    pending_analysis = max(0, total_evidence_count - analyzed_count)
    coverage = round((completed_analysis / total_evidence_count) * 100, 2) if total_evidence_count > 0 else 0.0

    scores = [r["epra_score"] for r in results if r.get("epra_score") is not None]
    avg_score = round(sum(scores) / len(scores), 2) if scores else 0.0
    highest_score = round(max(scores), 2) if scores else None
    lowest_score = round(min(scores), 2) if scores else None

    # Score distribution buckets: [90-100], [75-90), [50-75), [25-50), [0-25)
    bucket_90_100 = sum(1 for s in scores if s >= 90.0)
    bucket_75_90 = sum(1 for s in scores if 75.0 <= s < 90.0)
    bucket_50_75 = sum(1 for s in scores if 50.0 <= s < 75.0)
    bucket_25_50 = sum(1 for s in scores if 25.0 <= s < 50.0)
    bucket_0_25 = sum(1 for s in scores if s < 25.0)

    # Top records from the same ranked results
    sorted_results = sorted(
        results,
        key=lambda x: (x.get("rank") or 9999, -(x.get("epra_score") or 0.0))
    )
    top_5 = sorted_results[:5]

    return {
        "case_id": case.case_id if case else "CASE-001",
        "total_evidence": total_evidence_count,
        "analyzed_evidence": analyzed_count,
        "complete_analysis": completed_analysis,
        "completed_analysis": completed_analysis,
        "partial_analysis": partial_analysis,
        "pending_analysis": pending_analysis,
        "coverage_percentage": coverage,
        "critical": critical_count,
        "high": high_count,
        "medium": medium_count,
        "low": low_count,
        "very_low": very_low_count,
        "priority_breakdown": {
            "CRITICAL": critical_count,
            "HIGH": high_count,
            "MEDIUM": medium_count,
            "LOW": low_count,
            "VERY LOW": very_low_count,
        },
        "score_distribution": {
            "critical": critical_count,
            "high": high_count,
            "medium": medium_count,
            "low": low_count,
            "very_low": very_low_count,
            "pending": pending_analysis,
            "90-100": bucket_90_100,
            "75-90": bucket_75_90,
            "50-75": bucket_50_75,
            "25-50": bucket_25_50,
            "0-25": bucket_0_25
        },
        "average_epra_score": avg_score,
        "highest_score": highest_score,
        "lowest_score": lowest_score,
        "top_evidence": top_5,
        "priority_queue": sorted_results,
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

        canon_type = normalize_epra_evidence_type(
            filename=ev.file_name,
            raw_type=ev.file_type
        )

        results.append({
            "rank": epra.rank or 0,
            "evidence_id": ev.evidence_id,
            "file_name": ev.file_name,
            "evidence_type": canon_type,
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
    case: Optional[Case | str | int] = None,
    limit: Optional[int] = None,
    priority: Optional[str] = None,
    current_user: Optional[User] = None,
    case_id: Optional[str | int] = None
) -> List[Dict[str, Any]]:
    """
    Returns stored ranked evidence items for the case, ordered strictly by EPRA rank.
    Supports optional priority filtering and limit for top N evidence.
    """
    target = case if case is not None else case_id
    if target is None:
        raise ValueError("case or case_id must be provided")
    if isinstance(target, Case):
        c = target
    else:
        c = get_case_or_404(db, target)

    query = (
        db.query(EPRAResult, Evidence)
        .join(Evidence, EPRAResult.evidence_id == Evidence.id)
        .filter(EPRAResult.case_id == c.id)
    )

    if priority:
        query = query.filter(EPRAResult.priority.ilike(priority.strip()))

    query = query.order_by(EPRAResult.rank.asc(), EPRAResult.epra_score.desc())

    if limit and limit > 0:
        query = query.limit(limit)

    records = query.all()

    results = []
    for epra, ev in records:
        canon_type = normalize_epra_evidence_type(
            filename=ev.file_name,
            raw_type=ev.file_type
        )
        results.append({
            "rank": epra.rank or 0,
            "evidence_id": ev.evidence_id,
            "file_name": ev.file_name,
            "evidence_type": canon_type,
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
    case: Optional[Case | str | int] = None,
    evidence_identifier: Optional[str | int] = None,
    current_user: Optional[User] = None,
    case_id: Optional[str | int] = None,
    evidence_id: Optional[str | int] = None
) -> Dict[str, Any]:
    """
    Returns detailed forensic and EPRA scores for a single evidence item,
    ensuring it belongs strictly to the authorized parent case.
    """
    target = case if case is not None else case_id
    if target is None:
        raise ValueError("case or case_id must be provided")
    if isinstance(target, Case):
        c = target
    else:
        c = get_case_or_404(db, target)

    ev_ident = evidence_identifier if evidence_identifier is not None else evidence_id
    if ev_ident is None:
        raise ValueError("evidence_identifier or evidence_id must be provided")

    ident_str = str(ev_ident).strip()

    if ident_str.isdigit():
        evidence = db.query(Evidence).filter(
            Evidence.case_id == c.id,
            or_(
                Evidence.id == int(ident_str),
                Evidence.evidence_id == ident_str
            )
        ).first()
    else:
        evidence = db.query(Evidence).filter(
            Evidence.case_id == c.id,
            Evidence.evidence_id.ilike(ident_str)
        ).first()

    if not evidence:
        raise HTTPException(
            status_code=404,
            detail=f"Evidence '{ev_ident}' not found for this case"
        )

    epra = (
        db.query(EPRAResult)
        .filter(
            EPRAResult.case_id == c.id,
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

    canon_type = normalize_epra_evidence_type(
        filename=evidence.file_name,
        raw_type=evidence.file_type
    )

    return {
        "evidence_id": evidence.evidence_id,
        "file_name": evidence.file_name,
        "evidence_type": canon_type,
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
