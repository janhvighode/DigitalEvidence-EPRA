import os
import sys
from pathlib import Path
from typing import List, Optional, Dict, Any
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import desc

# Add AI modules and backend to path
BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROJECT_ROOT = os.path.abspath(os.path.join(BACKEND_DIR, ".."))
CBIR_DIR = os.path.join(PROJECT_ROOT, "ai_modules", "cbir")
REL_DIR = os.path.join(PROJECT_ROOT, "ai_modules", "relationship_graph")

for p in [BACKEND_DIR, PROJECT_ROOT, CBIR_DIR, REL_DIR]:
    if p not in sys.path:
        sys.path.insert(0, p)

from models.case import Case
from models.evidence import Evidence
from models.evidence_record import EvidenceRecord
from models.evidence_hash import EvidenceHash
from models.cbir_result import CBIRResult
from models.user import User
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from models.evidence_link import EvidenceLink
from services.notification_service import create_notification
from services.hash_service import HashService

from schemas.cbir import (
    CBIRImageEvidenceItem,
    CBIRImagesListResponse,
    CBIRCompareRequest,
    CBIRCandidateResult,
    CBIRSearchSummary,
    CBIRCompareResponse,
    CBIRCandidateDetailResponse,
    CaseSearchRequest,
    CaseSearchResponse
)

# Import Trisha's verified CBIR and retrieval algorithms
from feature_extractor import load_image, extract_features
from feature_database import get_case_evidence, get_evidence as get_cbir_evidence, insert_feature
from evidence_linker import insert_link, get_case_links
from image_search import (
    search_similar_images,
    format_investigator_image_result,
    render_investigator_image_card
)
from similarity import (
    compute_multi_signal_similarity,
    classify_match,
    compute_confidence_level,
    compute_investigation_recommendation,
    is_verification_required
)
from semantic_score import compute_semantic_score
from text_retrieval import (
    search_evidence_by_text,
    search_case_evidence,
    search_text_evidence,
    format_investigator_text_result
)
from context_retrieval import (
    search_context_evidence,
    search_evidence_by_context,
    format_investigator_context_result
)
from unified_retrieval import retrieve_evidence

SUPPORTED_IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".bmp", ".webp")

FORENSIC_DISCLAIMER = (
    "Visual similarity is advisory and requires investigative verification. "
    "CBIR results represent visual comparison assistance only. "
    "Similarity does not establish identity, common source, authenticity, or criminal association. "
    "Exact duplicate status requires cryptographic SHA-256 hash equality. "
    "Investigator verification is required."
)


def authorize_cyber_expert_case_access(case_id: Any, current_user: User, db: Session) -> Case:
    """
    Enforce strict JWT + Role 3 + Assigned-case authorization for Cyber Experts.
    """
    if current_user.role_id != 3:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to Cyber Experts only."
        )

    case = None
    if str(case_id).isdigit():
        case = db.query(Case).filter(Case.id == int(case_id)).first()
    if not case:
        case = db.query(Case).filter(Case.case_id == str(case_id)).first()

    if not case:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Case with ID {case_id} not found."
        )

    if case.cyber_expert_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access forbidden: Case is not assigned to the authenticated Cyber Expert."
        )

    return case


def authorize_case_access(
    db: Session,
    case_id: Any,
    current_user: Optional[User] = None
) -> Optional[Case]:
    """
    Enforce role-based case scoping:
    - Admin (role 1): allowed
    - Investigator (role 2): must be assigned to case
    - Cyber Expert (role 3): must be assigned to case
    - None (internal forensic testing): allow if case or evidence exists
    """
    clean_id = str(case_id).strip()
    case = None
    if clean_id.isdigit():
        case = db.query(Case).filter(Case.id == int(clean_id)).first()
    if not case:
        case = db.query(Case).filter(Case.case_id == clean_id).first()

    if current_user:
        if not case:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail=f"Case '{clean_id}' was not found."
            )
        role_id = getattr(current_user, "role_id", None)
        if role_id == 1:
            return case
        elif role_id == 2:
            if case.investigator_id != current_user.id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Access forbidden: Case '{clean_id}' is not assigned to you."
                )
            return case
        elif role_id == 3:
            if case.cyber_expert_id != current_user.id:
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN,
                    detail=f"Access forbidden: Case '{clean_id}' is not assigned to you."
                )
            return case
        else:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Access forbidden for this role."
            )

    return case


def is_eligible_image_evidence(
    mime_type: Optional[str] = None,
    file_extension: Optional[str] = None,
    category: Optional[str] = None,
    filename: Optional[str] = None
) -> bool:
    """
    Determine whether an evidence item represents eligible image evidence
    using real backend MIME type, category, or file extension.
    Non-image evidence (PDF, TXT, DOC, Audio, Video, etc.) returns False.
    """
    if mime_type and str(mime_type).strip().lower().startswith("image/"):
        return True

    ext = (file_extension or Path(filename or "").suffix).strip().lower()
    if ext in SUPPORTED_IMAGE_EXTENSIONS:
        return True

    cat = str(category or "").strip().lower()
    image_categories = {
        "image", "photo", "images", "photos", "crime_scene",
        "suspect", "person", "weapon", "vehicle"
    }
    if cat in image_categories:
        # Verify it's not explicitly non-image
        non_image_exts = {".pdf", ".txt", ".doc", ".docx", ".mp3", ".mp4", ".wav", ".avi", ".log"}
        if ext in non_image_exts:
            return False
        return True

    return False


def is_image_evidence(evidence: Any) -> bool:
    """Check if evidence record represents an image."""
    if not evidence:
        return False
    mime = getattr(evidence, "mime_type", getattr(evidence, "file_type", None))
    ext = getattr(evidence, "file_extension", None)
    fn = getattr(evidence, "file_name", getattr(evidence, "original_filename", ""))
    cat = getattr(evidence, "evidence_type", getattr(evidence, "category", None))
    return is_eligible_image_evidence(mime, ext, cat, fn)


def fetch_case_evidence_dynamically(db: Session, case_id: str) -> List[Dict[str, Any]]:
    """
    Fetch the complete current evidence collection belonging to case_id from
    all available genuine backend sources:
    1. DEPS Backend / EvidenceRecord table
    2. DEPS Backend / Evidence table (evidences)
    3. CBIR feature database (database/images.db)

    Deduplicates records by evidence_id and preserves real metadata.
    Never uses a hardcoded candidate list.
    """
    clean_case_id = str(case_id).strip()
    evidence_by_id: Dict[str, Dict[str, Any]] = {}

    # 1. Fetch from EvidenceRecord table
    try:
        db_records = db.query(EvidenceRecord).filter(
            EvidenceRecord.case_id == clean_case_id
        ).all()
        for r in db_records:
            ev_id = r.external_evidence_id or str(r.id)
            evidence_by_id[ev_id] = {
                "evidence_id": ev_id,
                "numeric_id": r.id,
                "case_id": r.case_id,
                "original_filename": r.original_filename,
                "filename": r.original_filename,
                "file_name": r.original_filename,
                "file_path": r.file_path,
                "image_path": r.file_path,
                "file_extension": r.file_extension,
                "mime_type": r.mime_type,
                "evidence_type": r.evidence_type or "Image",
                "category": r.evidence_type or "General",
                "sha256_hash": r.original_sha256 or r.current_sha256,
                "created_at": r.uploaded_at.isoformat() if r.uploaded_at else None,
                "description": r.notes or ""
            }
    except Exception:
        pass

    # 2. If no EvidenceRecord found, fetch from Evidence table
    if not evidence_by_id:
        try:
            case_row = None
            if clean_case_id.isdigit():
                case_row = db.query(Case).filter(Case.id == int(clean_case_id)).first()
            if not case_row:
                case_row = db.query(Case).filter(Case.case_id == clean_case_id).first()

            target_case_fk = case_row.id if case_row else (int(clean_case_id) if clean_case_id.isdigit() else None)
            if target_case_fk is not None:
                ev_rows = db.query(Evidence).filter(
                    Evidence.case_id == target_case_fk,
                    Evidence.status == "Active"
                ).all()

                ev_ids = [e.id for e in ev_rows]
                hash_rows = db.query(EvidenceHash).filter(EvidenceHash.evidence_id.in_(ev_ids)).all() if ev_ids else []
                h_map = {h.evidence_id: (h.sha256_hash or h.current_hash) for h in hash_rows}

                for ev in ev_rows:
                    ev_str_id = str(ev.evidence_id)
                    if ev_str_id not in evidence_by_id and str(ev.id) not in evidence_by_id:
                        evidence_by_id[ev_str_id] = {
                            "evidence_id": ev_str_id,
                            "numeric_id": ev.id,
                            "case_id": clean_case_id,
                            "original_filename": ev.file_name,
                            "filename": ev.file_name,
                            "file_name": ev.file_name,
                            "file_path": ev.file_path,
                            "image_path": ev.file_path,
                            "file_extension": Path(ev.file_name).suffix,
                            "mime_type": ev.file_type,
                            "evidence_type": "Image" if "image" in (ev.file_type or "").lower() else "Document",
                            "category": "Image" if "image" in (ev.file_type or "").lower() else "Document",
                            "sha256_hash": h_map.get(ev.id),
                            "created_at": str(ev.created_at) if ev.created_at else None,
                            "description": ""
                        }
        except Exception:
            pass

    # 3. Fetch from CBIR feature_database (SQLite images.db)
    if not evidence_by_id:
        try:
            cbir_records = get_case_evidence(clean_case_id)
            for c in cbir_records:
                ev_id = str(c.get("evidence_id"))
                if not ev_id:
                    continue
                img_p = c.get("image_path", "")
                fn = Path(img_p).name if img_p else ev_id

                if ev_id not in evidence_by_id:
                    evidence_by_id[ev_id] = {
                        "evidence_id": ev_id,
                        "numeric_id": None,
                        "case_id": clean_case_id,
                        "original_filename": fn,
                        "filename": fn,
                        "file_name": fn,
                        "file_path": img_p,
                        "image_path": img_p,
                        "file_extension": Path(fn).suffix,
                        "mime_type": "image/jpeg",
                        "evidence_type": c.get("category", "Image"),
                        "category": c.get("category", "Image"),
                        "sha256_hash": c.get("sha256_hash") or c.get("image_hash"),
                        "created_at": c.get("created_at"),
                        "description": c.get("description", "")
                    }
        except Exception:
            pass

    return list(evidence_by_id.values())


def get_case_image_evidence(case_id: Any, db: Session) -> CBIRImagesListResponse:
    """
    Fetch all genuine image evidence for the selected case.
    Populates the 'Select Query Image' dropdown or grid in the CBIR Working sidebar module.
    """
    clean_case_id = str(case_id).strip()
    all_evs = fetch_case_evidence_dynamically(db, clean_case_id)

    image_items = []
    for ev in all_evs:
        if is_eligible_image_evidence(
            mime_type=ev.get("mime_type"),
            file_extension=ev.get("file_extension"),
            category=ev.get("category"),
            filename=ev.get("file_name")
        ):
            image_items.append(
                CBIRImageEvidenceItem(
                    id=ev.get("numeric_id") or 0,
                    evidence_id=str(ev.get("evidence_id")),
                    file_name=ev.get("file_name", ""),
                    file_type=ev.get("mime_type") or "image/jpeg",
                    file_size=0,
                    created_at=ev.get("created_at")
                )
            )

    c_int = int(clean_case_id) if clean_case_id.isdigit() else 0
    return CBIRImagesListResponse(
        case_id=c_int,
        total_images=len(image_items),
        images=image_items
    )


def run_cbir_comparison(
    case_id: Any,
    req: CBIRCompareRequest,
    db: Session,
    current_user: Optional[User] = None
) -> CBIRCompareResponse:
    """
    Execute Content-Based Image Retrieval strictly within the selected case.
    Compares query image against all remaining eligible same-case images.
    """
    clean_case_id = str(req.case_id or case_id).strip()
    clean_query_id = req.resolved_query_evidence_id

    if not clean_query_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Query evidence identifier ('query_evidence_id' or 'evidence_id') is required."
        )

    # 1. Fetch all evidence dynamically belonging to this case
    all_case_evidence = fetch_case_evidence_dynamically(db, clean_case_id)
    ev_map = {str(e["evidence_id"]): e for e in all_case_evidence}
    for e in all_case_evidence:
        if e.get("numeric_id"):
            ev_map[str(e["numeric_id"])] = e

    # 2. Locate query evidence within the case
    query_item = ev_map.get(clean_query_id)

    if not query_item:
        # Check whether this evidence item belongs to a DIFFERENT case
        wrong_case_rec = None
        try:
            wrong_case_rec = db.query(EvidenceRecord).filter(
                (EvidenceRecord.external_evidence_id == clean_query_id) |
                (EvidenceRecord.id == int(clean_query_id) if clean_query_id.isdigit() else False)
            ).first()
        except Exception:
            pass

        if not wrong_case_rec:
            try:
                wrong_case_rec = db.query(Evidence).filter(
                    (Evidence.evidence_id == clean_query_id) |
                    (Evidence.id == int(clean_query_id) if clean_query_id.isdigit() else False)
                ).first()
            except Exception:
                pass

        if wrong_case_rec and str(wrong_case_rec.case_id) != clean_case_id:
            if isinstance(wrong_case_rec, Evidence) and current_user:
                raise HTTPException(
                    status_code=status.HTTP_404_NOT_FOUND,
                    detail=f"Query evidence {clean_query_id} not found in case {clean_case_id}."
                )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Selected evidence '{clean_query_id}' belongs to another case and does not belong to this case."
            )

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Selected evidence was not found."
        )

    query_fn = query_item.get("original_filename") or query_item.get("file_name") or clean_query_id

    # 3. Validate query evidence is an eligible image
    if not is_eligible_image_evidence(
        mime_type=query_item.get("mime_type"),
        file_extension=query_item.get("file_extension"),
        category=query_item.get("category"),
        filename=query_fn
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Selected evidence '{query_fn}' is not a supported image / eligible image evidence."
        )

    # 4. Filter all eligible same-case images
    eligible_images = [
        ev for ev in all_case_evidence
        if is_eligible_image_evidence(
            mime_type=ev.get("mime_type"),
            file_extension=ev.get("file_extension"),
            category=ev.get("category"),
            filename=ev.get("original_filename") or ev.get("file_name")
        )
    ]
    eligible_image_count = len(eligible_images)

    # 5. Exclude query image itself (Self-Match Exclusion: N - 1 candidates)
    actual_query_ev_id = str(query_item["evidence_id"])
    candidates = [
        ev for ev in eligible_images
        if str(ev["evidence_id"]) != actual_query_ev_id and
           (not query_item.get("numeric_id") or ev.get("numeric_id") != query_item.get("numeric_id"))
    ]
    candidates_compared = len(candidates)

    # 6. Zero candidate handling (returns clean 200 HTTP response)
    if candidates_compared == 0:
        summary = CBIRSearchSummary(
            total_same_case_images=eligible_image_count,
            candidates_analyzed=0,
            query_excluded_id=actual_query_ev_id,
            result_count=0
        )
        return CBIRCompareResponse(
            status="no_candidates",
            message=f"No other eligible image evidence is available in case '{clean_case_id}' for comparison.",
            case_id=int(clean_case_id) if clean_case_id.isdigit() else clean_case_id,
            query_evidence_id=actual_query_ev_id,
            query_filename=query_fn,
            total_case_evidence=len(all_case_evidence),
            eligible_image_count=eligible_image_count,
            candidates_compared=0,
            summary=summary,
            results=[],
            cards=[],
            forensic_disclaimer=FORENSIC_DISCLAIMER,
            forensic_notice=FORENSIC_DISCLAIMER
        )

    # 7. Extract or resolve query SHA-256 and visual features
    query_sha = query_item.get("sha256_hash")
    query_path = query_item.get("file_path") or query_item.get("image_path")
    if not query_sha and query_path and os.path.isfile(query_path):
        try:
            query_sha = HashService.generate_sha256(query_path)
        except Exception:
            pass

    query_features = None
    if query_path and os.path.isfile(query_path):
        q_img = load_image(query_path)
        if q_img is not None:
            query_features = extract_features(q_img)

    raw_results = []
    investigator_cards = []

    # 8. Compare against each candidate in the same case
    for cand in candidates:
        cand_id = str(cand.get("evidence_id"))
        cand_fn = cand.get("original_filename") or cand.get("file_name") or cand_id
        cand_path = cand.get("file_path") or cand.get("image_path")

        cand_sha = cand.get("sha256_hash")
        if not cand_sha and cand_path and os.path.isfile(cand_path):
            try:
                cand_sha = HashService.generate_sha256(cand_path)
            except Exception:
                pass

        # Bitwise exact duplicate check via SHA-256
        is_exact_dup = False
        if query_sha and cand_sha and str(query_sha).lower().strip() == str(cand_sha).lower().strip():
            is_exact_dup = True

        if is_exact_dup:
            vis_score = 1.0
            signals = {
                "edge_similarity": 1.0,
                "orb_similarity": 1.0,
                "color_similarity": 1.0,
                "grayscale_similarity": 1.0
            }
            classification = "Exact Duplicate"
            confidence = "High"
            ver_req = False
            rec = "KEEP_FOR_INVESTIGATION"
            reason = "SHA-256 hashes are identical; files are exact bit-for-bit duplicates."
            sem_score = 1.00
        else:
            cand_features = None
            if cand_path and os.path.isfile(cand_path):
                c_img = load_image(cand_path)
                if c_img is not None:
                    cand_features = extract_features(c_img)

            if query_features is not None and cand_features is not None:
                vis_score, signals = compute_multi_signal_similarity(query_features, cand_features)
            else:
                vis_score = 0.0
                signals = {
                    "edge_similarity": 0.0,
                    "orb_similarity": 0.0,
                    "color_similarity": 0.0,
                    "grayscale_similarity": 0.0
                }

            classification = classify_match(vis_score, is_exact_hash_match=False)
            confidence = compute_confidence_level(vis_score, is_exact_hash_match=False)
            ver_req = is_verification_required(vis_score, is_exact_hash_match=False)
            rec = compute_investigation_recommendation(classification=classification, score=vis_score, is_exact_hash_match=False)
            sem_score = compute_semantic_score(classification=classification, similarity_score=vis_score, is_exact_hash_match=False)

            if vis_score >= 0.93:
                reason = f"Very strong visual candidate (score {vis_score:.4f}). Forensic verification required."
            elif vis_score >= 0.85:
                reason = f"Strong visual candidate (score {vis_score:.4f}) supported by multi-signal agreement. Verification required."
            elif vis_score >= 0.70:
                reason = f"Possible visual resemblance (score {vis_score:.4f}). Verification required."
            elif vis_score >= 0.50:
                reason = f"Weak visual resemblance (score {vis_score:.4f}). Verification required."
            else:
                reason = "No significant visual match found."

        res_dict = {
            "candidate_db_id": cand.get("numeric_id"),
            "case_id": clean_case_id,
            "query_evidence_id": actual_query_ev_id,
            "query_filename": query_fn,
            "candidate_evidence_id": cand_id,
            "candidate_filename": cand_fn,
            "edge_similarity": round(float(signals.get("edge_similarity", vis_score)), 4),
            "orb_similarity": round(float(signals.get("orb_similarity", vis_score)), 4),
            "color_similarity": round(float(signals.get("color_similarity", vis_score)), 4),
            "grayscale_similarity": round(float(signals.get("grayscale_similarity", vis_score)), 4),
            "visual_similarity_score": round(float(vis_score), 4),
            "semantic_score": round(float(sem_score), 2),
            "sha256_exact_duplicate": is_exact_dup,
            "classification": classification,
            "confidence": confidence,
            "confidence_level": confidence,
            "verification_required": ver_req,
            "recommendation": rec,
            "investigation_recommendation": rec,
            "reason": reason,
            "signals": signals
        }
        raw_results.append(res_dict)

        # Generate clutter-free card with zero raw SHA or system paths
        try:
            card_data = format_investigator_image_result(res_dict)
            if card_data:
                investigator_cards.append(card_data)
        except Exception:
            pass

    # 9. Deterministic Ranking: score descending, then candidate_evidence_id ascending
    raw_results.sort(
        key=lambda item: (-item["visual_similarity_score"], str(item["candidate_evidence_id"]))
    )

    for rank_idx, item in enumerate(raw_results, start=1):
        item["rank"] = rank_idx

    # 10. Persist results into TiDB cbir_results table where feasible
    try:
        q_num = query_item.get("numeric_id")
        c_num = int(clean_case_id) if clean_case_id.isdigit() else None
        if c_num and q_num:
            db.query(CBIRResult).filter(
                CBIRResult.case_id == c_num,
                CBIRResult.query_evidence_id == q_num
            ).delete(synchronize_session=False)

            for item in raw_results:
                if item.get("candidate_db_id"):
                    db_record = CBIRResult(
                        case_id=c_num,
                        query_evidence_id=q_num,
                        candidate_evidence_id=item["candidate_db_id"],
                        visual_similarity_score=item["visual_similarity_score"],
                        semantic_score=item["semantic_score"],
                        edge_similarity=item["edge_similarity"],
                        orb_similarity=item["orb_similarity"],
                        color_similarity=item["color_similarity"],
                        grayscale_similarity=item["grayscale_similarity"],
                        classification=item["classification"],
                        confidence_level=item["confidence_level"],
                        verification_required=item["verification_required"],
                        recommendation=item["recommendation"],
                        reason=item["reason"],
                        sha256_exact_duplicate=item["sha256_exact_duplicate"],
                        rank=item["rank"]
                    )
                    db.add(db_record)
            db.commit()
    except Exception:
        db.rollback()

    # 11. Apply server-side filters if requested
    filtered_results = raw_results
    if req.classification and req.classification.strip() not in ("All", ""):
        target_cls = req.classification.strip().lower()
        filtered_results = [r for r in filtered_results if r["classification"].lower() == target_cls]

    if req.min_visual_similarity and req.min_visual_similarity > 0.0:
        filtered_results = [r for r in filtered_results if r["visual_similarity_score"] >= req.min_visual_similarity]

    # Apply Top-K slicing post-ranking
    k_limit = req.top_k if req.top_k and req.top_k > 0 else 50
    sliced_results = filtered_results[:k_limit]

    result_models = [
        CBIRCandidateResult(
            case_id=r["case_id"],
            query_evidence_id=r["query_evidence_id"],
            query_filename=r["query_filename"],
            candidate_evidence_id=r["candidate_evidence_id"],
            candidate_filename=r["candidate_filename"],
            edge_similarity=r["edge_similarity"],
            orb_similarity=r["orb_similarity"],
            color_similarity=r["color_similarity"],
            grayscale_similarity=r["grayscale_similarity"],
            visual_similarity_score=r["visual_similarity_score"],
            semantic_score=r["semantic_score"],
            sha256_exact_duplicate=r["sha256_exact_duplicate"],
            classification=r["classification"],
            confidence=r["confidence"],
            confidence_level=r["confidence_level"],
            verification_required=r["verification_required"],
            recommendation=r["recommendation"],
            investigation_recommendation=r["investigation_recommendation"],
            reason=r["reason"],
            rank=r["rank"]
        )
        for r in sliced_results
    ]

    summary = CBIRSearchSummary(
        total_same_case_images=eligible_image_count,
        candidates_analyzed=candidates_compared,
        query_excluded_id=actual_query_ev_id,
        result_count=len(result_models)
    )

    return CBIRCompareResponse(
        status="Success",
        message=f"CBIR comparison completed against {candidates_compared} eligible candidates.",
        case_id=int(clean_case_id) if clean_case_id.isdigit() else clean_case_id,
        query_evidence_id=actual_query_ev_id,
        query_filename=query_fn,
        total_case_evidence=len(all_case_evidence),
        eligible_image_count=eligible_image_count,
        candidates_compared=candidates_compared,
        summary=summary,
        results=result_models,
        cards=investigator_cards[:k_limit],
        forensic_disclaimer=FORENSIC_DISCLAIMER,
        forensic_notice=FORENSIC_DISCLAIMER
    )


def ensure_case_evidence_synchronized(db: Session, clean_case_id: str) -> None:
    """
    Dynamically synchronize real DEPS evidence and relationship links from the
    database into Member-3's feature_database and evidence_linker.
    Ensures text, context, and unified search operate on real DEPS evidence,
    supporting newly registered cases and evidences without any hardcoding.
    """
    case_row = None
    if str(clean_case_id).isdigit():
        case_row = db.query(Case).filter(Case.id == int(clean_case_id)).first()
    if not case_row:
        case_row = db.query(Case).filter(Case.case_id == str(clean_case_id)).first()

    # 1. Sync from Evidence table (active cases)
    if case_row:
        ev_rows = db.query(Evidence).filter(
            Evidence.case_id == case_row.id,
            Evidence.status == "Active"
        ).all()
        for ev in ev_rows:
            ev_id = str(ev.evidence_id)
            img_p = ev.file_path or f"uploads/{ev.file_name}"
            insert_feature(
                case_id=str(clean_case_id),
                evidence_id=ev_id,
                image_path=img_p,
                feature_path=img_p,
                category=ev.file_type or "Evidence",
                description=f"{ev.file_name} in {clean_case_id}"
            )

        # 2. Sync from PossibleEntity & PossibleEntityEvidenceLink
        try:
            entities = db.query(PossibleEntity).filter(PossibleEntity.case_id == case_row.id).all()
            if entities:
                existing_links = get_case_links(str(clean_case_id))
                existing_tuples = {(str(l.get("evidence")), str(l.get("suspect")), str(l.get("device"))) for l in existing_links}
                for ent in entities:
                    s_name = ent.suspect_name or ent.suspect_id
                    pel_links = db.query(PossibleEntityEvidenceLink).filter(PossibleEntityEvidenceLink.entity_id == ent.id).all()
                    for pel in pel_links:
                        linked_ev = db.query(Evidence).filter(Evidence.id == pel.evidence_id).first()
                        if linked_ev:
                            ev_str = str(linked_ev.evidence_id)
                            tup = (ev_str, s_name, "None")
                            if tup not in existing_tuples:
                                insert_link(
                                    evidence=ev_str,
                                    suspect=s_name,
                                    device="None",
                                    case_id=str(clean_case_id),
                                    evidence_type=linked_ev.file_type or "Evidence",
                                    confidence=float(ent.confidence_score or 0.85),
                                    relationship_type="ASSOCIATED_WITH"
                                )
                                existing_tuples.add(tup)
        except Exception:
            pass

        # 3. Sync from EvidenceLink table
        try:
            db_links = db.query(EvidenceLink).filter(EvidenceLink.case_id == case_row.id).all()
            if db_links:
                existing_links = get_case_links(str(clean_case_id))
                existing_tuples = {(str(l.get("evidence")), str(l.get("suspect")), str(l.get("device"))) for l in existing_links}
                for l in db_links:
                    ev_item = db.query(Evidence).filter(Evidence.id == l.evidence_id).first()
                    ev_str = str(ev_item.evidence_id) if ev_item else str(l.evidence_id)
                    s_name = str(l.suspect_name or "None")
                    d_name = str(l.device_name or "None")
                    tup = (ev_str, s_name, d_name)
                    if tup not in existing_tuples:
                        insert_link(
                            evidence=ev_str,
                            suspect=s_name,
                            device=d_name,
                            case_id=str(clean_case_id),
                            evidence_type=ev_item.file_type if ev_item else "Evidence",
                            confidence=1.0,
                            relationship_type=l.relationship_type or "ASSOCIATED_WITH"
                        )
                        existing_tuples.add(tup)
        except Exception:
            pass

    # 4. Sync from EvidenceRecord table (vault records)
    try:
        rec_rows = db.query(EvidenceRecord).filter(
            EvidenceRecord.case_id == str(clean_case_id)
        ).all()
        for r in rec_rows:
            ev_id = str(r.external_evidence_id or r.id)
            img_p = r.file_path or f"uploads/{r.stored_filename or r.original_filename}"
            insert_feature(
                case_id=str(clean_case_id),
                evidence_id=ev_id,
                image_path=img_p,
                feature_path=img_p,
                category=r.evidence_type or "Evidence",
                sha256_hash=r.original_sha256 or r.current_sha256,
                description=r.notes or f"{r.original_filename} in {clean_case_id}"
            )
    except Exception:
        pass


def search_case_text_service(
    db: Session,
    case_id: str,
    query_text: Optional[str] = "",
    top_k: int = 10,
    search_mode: str = "text",
    max_hops: int = 2,
    current_user: Optional[User] = None
) -> CaseSearchResponse:
    """
    Integrates Trisha's case-level text evidence retrieval with strict case isolation.
    """
    clean_case_id = str(case_id).strip()
    authorize_case_access(db, clean_case_id, current_user)
    ensure_case_evidence_synchronized(db, clean_case_id)

    q_str = str(query_text or "").strip()

    if search_mode in ["all", "case_search"]:
        results = search_case_evidence(
            case_id=clean_case_id,
            query_text=q_str,
            top_k=top_k,
            search_mode=search_mode,
            max_hops=max_hops
        )
    else:
        results = search_evidence_by_text(
            case_id=clean_case_id,
            query_text=q_str,
            top_k=top_k,
            return_dict=True
        )

    if isinstance(results, dict):
        res_list = results.get("results", []) or results.get("ranked_evidence", [])
        status_str = results.get("status", "Success" if res_list else "no_data_found")
        msg = results.get("message") or (
            f"Found {len(res_list)} matching evidence items in case '{clean_case_id}'."
            if res_list else f"No relevant evidence found for '{q_str}' in {clean_case_id}."
        )
    else:
        res_list = results if isinstance(results, list) else []
        status_str = "Success" if res_list else "no_data_found"
        msg = (
            f"Found {len(res_list)} matching evidence items in case '{clean_case_id}'."
            if res_list else f"No relevant evidence found for '{q_str}' in {clean_case_id}."
        )

    return CaseSearchResponse(
        status=status_str,
        message=msg,
        case_id=clean_case_id,
        search_query=q_str,
        search_box_label="Search evidence in this case...",
        results_count=len(res_list),
        results=res_list,
        ranked_evidence=res_list,
        forensic_notice="Search results are derived from persisted evidence metadata and text extractions."
    )


def search_case_context_service(
    db: Session,
    case_id: str,
    query_text: Optional[str] = "",
    max_hops: int = 2,
    top_k: int = 10,
    current_user: Optional[User] = None
) -> CaseSearchResponse:
    """
    Integrates Trisha's case-level context evidence retrieval using the case relationship graph.
    """
    clean_case_id = str(case_id).strip()
    authorize_case_access(db, clean_case_id, current_user)
    ensure_case_evidence_synchronized(db, clean_case_id)

    q_str = str(query_text or "").strip()

    results = search_context_evidence(
        case_id=clean_case_id,
        query_text=q_str,
        max_hops=max_hops,
        top_k=top_k
    )

    if isinstance(results, dict):
        res_list = results.get("results", []) or results.get("ranked_evidence", [])
        status_str = results.get("status", "Success" if res_list else "no_data_found")
        msg = results.get("message") or (
            f"Found {len(res_list)} contextually related items in case '{clean_case_id}'."
            if res_list else f"No related contextual evidence found for '{q_str}' in {clean_case_id}."
        )
    else:
        res_list = results if isinstance(results, list) else []
        status_str = "Success" if res_list else "no_data_found"
        msg = (
            f"Found {len(res_list)} contextually related items in case '{clean_case_id}'."
            if res_list else f"No related contextual evidence found for '{q_str}' in {clean_case_id}."
        )

    return CaseSearchResponse(
        status=status_str,
        message=msg,
        case_id=clean_case_id,
        search_query=q_str,
        search_box_label="Search evidence in this case...",
        results_count=len(res_list),
        results=res_list,
        ranked_evidence=res_list,
        forensic_notice="Contextual results derived from genuine case relationship graph traversals."
    )


def search_case_unified_service(
    db: Session,
    case_id: str,
    query_type: str = "text",
    query_text: Optional[str] = None,
    query_evidence_id: Optional[str] = None,
    query_image_path: Optional[str] = None,
    top_k: int = 10,
    current_user: Optional[User] = None
) -> Dict[str, Any]:
    """
    Unified forensic retrieval entry point wrapping Trisha's unified_retrieval module.
    """
    clean_case_id = str(case_id).strip()
    authorize_case_access(db, clean_case_id, current_user)
    ensure_case_evidence_synchronized(db, clean_case_id)

    return retrieve_evidence(
        case_id=clean_case_id,
        query_type=query_type,
        query_image_path=query_image_path,
        query_evidence_id=query_evidence_id,
        query_text=query_text,
        top_k=top_k,
        include_graph=True
    )


def get_stored_cbir_results(
    case_id: Any,
    query_evidence_id: Optional[Any],
    db: Session
) -> CBIRCompareResponse:
    """
    Retrieve previously persisted CBIR comparison results from TiDB Cloud.
    """
    clean_case_id = str(case_id).strip()
    c_int = int(clean_case_id) if clean_case_id.isdigit() else 0

    query = db.query(CBIRResult).filter(CBIRResult.case_id == c_int)
    if query_evidence_id:
        q_int = int(query_evidence_id) if str(query_evidence_id).isdigit() else None
        if q_int:
            query = query.filter(CBIRResult.query_evidence_id == q_int)

    db_rows = query.order_by(CBIRResult.rank.asc()).all()

    if not db_rows:
        return CBIRCompareResponse(
            case_id=clean_case_id,
            query_evidence_id="",
            query_filename="",
            summary=CBIRSearchSummary(
                total_same_case_images=0,
                candidates_analyzed=0,
                query_excluded_id="",
                result_count=0
            ),
            results=[],
            forensic_disclaimer=FORENSIC_DISCLAIMER
        )

    ev_ids = list({r.query_evidence_id for r in db_rows} | {r.candidate_evidence_id for r in db_rows})
    ev_map = {ev.id: ev for ev in db.query(Evidence).filter(Evidence.id.in_(ev_ids)).all()}

    q_ev_id = db_rows[0].query_evidence_id
    q_ev = ev_map.get(q_ev_id)
    q_str = str(q_ev.evidence_id) if q_ev else str(q_ev_id)
    q_fn = q_ev.file_name if q_ev else ""

    results = []
    for r in db_rows:
        c_ev = ev_map.get(r.candidate_evidence_id)
        c_str = str(c_ev.evidence_id) if c_ev else str(r.candidate_evidence_id)
        c_fn = c_ev.file_name if c_ev else ""

        results.append(
            CBIRCandidateResult(
                case_id=clean_case_id,
                query_evidence_id=q_str,
                query_filename=q_fn,
                candidate_evidence_id=c_str,
                candidate_filename=c_fn,
                edge_similarity=r.edge_similarity,
                orb_similarity=r.orb_similarity,
                color_similarity=r.color_similarity,
                grayscale_similarity=r.grayscale_similarity,
                visual_similarity_score=r.visual_similarity_score,
                semantic_score=r.semantic_score,
                sha256_exact_duplicate=r.sha256_exact_duplicate,
                classification=r.classification,
                confidence=r.confidence_level,
                confidence_level=r.confidence_level,
                verification_required=r.verification_required,
                recommendation=r.recommendation,
                investigation_recommendation=r.recommendation,
                reason=r.reason or "",
                rank=r.rank
            )
        )

    summary = CBIRSearchSummary(
        total_same_case_images=len(results) + 1,
        candidates_analyzed=len(results),
        query_excluded_id=q_str,
        result_count=len(results)
    )

    return CBIRCompareResponse(
        case_id=clean_case_id,
        query_evidence_id=q_str,
        query_filename=q_fn,
        summary=summary,
        results=results,
        forensic_disclaimer=FORENSIC_DISCLAIMER
    )


def get_cbir_candidate_detail(
    case_id: Any,
    candidate_evidence_id: Any,
    query_evidence_id: Optional[Any],
    db: Session
) -> CBIRCandidateDetailResponse:
    """
    Get detailed breakdown for a single candidate image for the View Result Details modal.
    """
    clean_case_id = str(case_id).strip()
    c_int = int(clean_case_id) if clean_case_id.isdigit() else 0
    cand_int = int(candidate_evidence_id) if str(candidate_evidence_id).isdigit() else 0

    query = db.query(CBIRResult).filter(
        CBIRResult.case_id == c_int,
        CBIRResult.candidate_evidence_id == cand_int
    )
    if query_evidence_id and str(query_evidence_id).isdigit():
        query = query.filter(CBIRResult.query_evidence_id == int(query_evidence_id))

    record = query.first()
    if not record:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Candidate comparison record not found for evidence {candidate_evidence_id}."
        )

    q_ev = db.query(Evidence).filter(Evidence.id == record.query_evidence_id).first()
    c_ev = db.query(Evidence).filter(Evidence.id == record.candidate_evidence_id).first()

    cand_result = CBIRCandidateResult(
        case_id=clean_case_id,
        query_evidence_id=str(q_ev.evidence_id) if q_ev else str(record.query_evidence_id),
        query_filename=q_ev.file_name if q_ev else "",
        candidate_evidence_id=str(c_ev.evidence_id) if c_ev else str(record.candidate_evidence_id),
        candidate_filename=c_ev.file_name if c_ev else "",
        edge_similarity=record.edge_similarity,
        orb_similarity=record.orb_similarity,
        color_similarity=record.color_similarity,
        grayscale_similarity=record.grayscale_similarity,
        visual_similarity_score=record.visual_similarity_score,
        semantic_score=record.semantic_score,
        sha256_exact_duplicate=record.sha256_exact_duplicate,
        classification=record.classification,
        confidence=record.confidence_level,
        confidence_level=record.confidence_level,
        verification_required=record.verification_required,
        recommendation=record.recommendation,
        investigation_recommendation=record.recommendation,
        reason=record.reason or "",
        rank=record.rank
    )

    signals = {
        "edge_similarity": record.edge_similarity,
        "orb_similarity": record.orb_similarity,
        "color_similarity": record.color_similarity,
        "grayscale_similarity": record.grayscale_similarity,
        "visual_similarity_score": record.visual_similarity_score,
        "sha256_exact_duplicate": record.sha256_exact_duplicate
    }

    return CBIRCandidateDetailResponse(
        candidate=cand_result,
        signals=signals,
        forensic_notice=FORENSIC_DISCLAIMER
    )
