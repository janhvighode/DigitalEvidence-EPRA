import os
import sys
from typing import List, Optional, Dict, Any
from fastapi import HTTPException, status
from sqlalchemy.orm import Session
from sqlalchemy import desc

# Add AI modules and backend to path
BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
PROJECT_ROOT = os.path.abspath(os.path.join(BACKEND_DIR, ".."))
CBIR_DIR = os.path.join(PROJECT_ROOT, "ai_modules", "cbir")

for p in [BACKEND_DIR, PROJECT_ROOT, CBIR_DIR]:
    if p not in sys.path:
        sys.path.insert(0, p)

from models.case import Case
from models.evidence import Evidence
from models.evidence_hash import EvidenceHash
from models.cbir_result import CBIRResult
from models.user import User
from services.notification_service import create_notification

from schemas.cbir import (
    CBIRImageEvidenceItem,
    CBIRImagesListResponse,
    CBIRCompareRequest,
    CBIRCandidateResult,
    CBIRSearchSummary,
    CBIRCompareResponse,
    CBIRCandidateDetailResponse
)

# Import Trisha's verified CBIR algorithms
from feature_extractor import load_image, extract_features
from similarity import (
    compute_multi_signal_similarity,
    classify_match,
    compute_confidence_level,
    compute_investigation_recommendation,
    is_verification_required
)
from semantic_score import compute_semantic_score

SUPPORTED_IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".bmp", ".webp")

FORENSIC_DISCLAIMER = (
    "Visual similarity is advisory and requires investigative verification. "
    "It does not establish person identity, ownership, authenticity, or criminal culpability. "
    "Exact duplicate status requires cryptographic SHA-256 hash equality."
)


def authorize_cyber_expert_case_access(case_id: int, current_user: User, db: Session) -> Case:
    """
    Enforce strict JWT + Role 3 + Assigned-case authorization.
    Cyber Experts can only access cases assigned to them.
    """
    if current_user.role_id != 3:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Access restricted to Cyber Experts only."
        )

    case = db.query(Case).filter(Case.id == case_id).first()
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


def is_image_evidence(evidence: Evidence) -> bool:
    """Check if evidence record represents an image."""
    if not evidence:
        return False
    if evidence.file_type and "image" in evidence.file_type.lower():
        return True
    name = (evidence.file_name or "").lower()
    path = (evidence.file_path or "").lower()
    return any(name.endswith(ext) or path.endswith(ext) for ext in SUPPORTED_IMAGE_EXTENSIONS)


def get_case_image_evidence(case_id: int, db: Session) -> CBIRImagesListResponse:
    """
    Fetch all genuine image evidence for the selected case.
    Used by the Cyber Expert standalone sidebar module for query selection.
    """
    evidences = db.query(Evidence).filter(
        Evidence.case_id == case_id,
        Evidence.status == "Active"
    ).all()

    image_items = []
    for ev in evidences:
        if is_image_evidence(ev):
            image_items.append(
                CBIRImageEvidenceItem(
                    id=ev.id,
                    evidence_id=str(ev.evidence_id),
                    file_name=ev.file_name,
                    file_type=ev.file_type or "image/jpeg",
                    file_size=ev.file_size or 0,
                    created_at=str(ev.created_at) if ev.created_at else None
                )
            )

    return CBIRImagesListResponse(
        case_id=case_id,
        total_images=len(image_items),
        images=image_items
    )


def run_cbir_comparison(
    case_id: int,
    req: CBIRCompareRequest,
    db: Session
) -> CBIRCompareResponse:
    """
    Execute Content-Based Image Retrieval strictly within the selected case.
    Compares query image against all remaining eligible same-case images.
    """
    # 1. Fetch query evidence
    query_ev = db.query(Evidence).filter(
        Evidence.id == req.query_evidence_id,
        Evidence.case_id == case_id
    ).first()

    if not query_ev:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Query evidence {req.query_evidence_id} not found in case {case_id}."
        )

    if not is_image_evidence(query_ev):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Selected evidence '{query_ev.file_name}' is not a supported image."
        )

    # 2. Fetch all same-case images
    all_evs = db.query(Evidence).filter(
        Evidence.case_id == case_id,
        Evidence.status == "Active"
    ).all()

    same_case_images = [ev for ev in all_evs if is_image_evidence(ev)]
    total_same_case = len(same_case_images)

    # 3. Exclude query image itself (Self-Match Exclusion)
    candidates = [ev for ev in same_case_images if ev.id != query_ev.id]
    candidates_count = len(candidates)

    if candidates_count == 0:
        # Case has only 1 image (the query image) or 0 other images
        summary = CBIRSearchSummary(
            total_same_case_images=total_same_case,
            candidates_analyzed=0,
            query_excluded_id=str(query_ev.evidence_id),
            result_count=0
        )
        return CBIRCompareResponse(
            case_id=case_id,
            query_evidence_id=str(query_ev.evidence_id),
            query_filename=query_ev.file_name,
            summary=summary,
            results=[],
            forensic_disclaimer=FORENSIC_DISCLAIMER
        )

    # 4. Fetch verified hashes for SHA-256 exact-duplicate evaluation
    ev_ids = [query_ev.id] + [c.id for c in candidates]
    hashes = db.query(EvidenceHash).filter(EvidenceHash.evidence_id.in_(ev_ids)).all()
    hash_map: Dict[int, str] = {}
    for h in hashes:
        digest = h.verified_at and (h.sha256_hash or h.current_hash)
        if not digest:
            digest = h.current_hash or h.sha256_hash
        if digest:
            hash_map[h.evidence_id] = str(digest).lower().strip()

    query_hash = hash_map.get(query_ev.id)

    # 5. Extract query visual features
    query_features = None
    if query_ev.file_path and os.path.isfile(query_ev.file_path):
        q_img = load_image(query_ev.file_path)
        if q_img is not None:
            query_features = extract_features(q_img)

    raw_results = []

    # 6. Compare against each candidate
    for cand in candidates:
        cand_hash = hash_map.get(cand.id)

        # Cryptographic exact duplicate check
        is_exact_dup = False
        if query_hash and cand_hash and query_hash == cand_hash:
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
            if cand.file_path and os.path.isfile(cand.file_path):
                c_img = load_image(cand.file_path)
                if c_img is not None:
                    cand_features = extract_features(c_img)

            if query_features is not None and cand_features is not None:
                vis_score, signals = compute_multi_signal_similarity(query_features, cand_features)
            else:
                # If disk images are unavailable, provide safe default
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

        raw_results.append({
            "candidate_db_id": cand.id,
            "case_id": case_id,
            "query_evidence_id": str(query_ev.evidence_id),
            "query_filename": query_ev.file_name,
            "candidate_evidence_id": str(cand.evidence_id),
            "candidate_filename": cand.file_name,
            "edge_similarity": round(float(signals.get("edge_similarity", vis_score)), 4),
            "orb_similarity": round(float(signals.get("orb_similarity", vis_score)), 4),
            "color_similarity": round(float(signals.get("color_similarity", vis_score)), 4),
            "grayscale_similarity": round(float(signals.get("grayscale_similarity", vis_score)), 4),
            "visual_similarity_score": round(float(vis_score), 4),
            "semantic_score": round(float(sem_score), 2),
            "sha256_exact_duplicate": is_exact_dup,
            "classification": classification,
            "confidence": confidence,
            "verification_required": ver_req,
            "recommendation": rec,
            "reason": reason,
            "signals": signals
        })

    # 7. Deterministic Ranking: score descending, then candidate_evidence_id ascending
    raw_results.sort(
        key=lambda item: (-item["visual_similarity_score"], str(item["candidate_evidence_id"]))
    )

    for rank_idx, item in enumerate(raw_results, start=1):
        item["rank"] = rank_idx

    # 8. Persist results into TiDB cbir_results table
    try:
        # Remove stale runs for this query evidence
        db.query(CBIRResult).filter(
            CBIRResult.case_id == case_id,
            CBIRResult.query_evidence_id == query_ev.id
        ).delete(synchronize_session=False)

        for item in raw_results:
            db_record = CBIRResult(
                case_id=case_id,
                query_evidence_id=query_ev.id,
                candidate_evidence_id=item["candidate_db_id"],
                visual_similarity_score=item["visual_similarity_score"],
                semantic_score=item["semantic_score"],
                edge_similarity=item["edge_similarity"],
                orb_similarity=item["orb_similarity"],
                color_similarity=item["color_similarity"],
                grayscale_similarity=item["grayscale_similarity"],
                classification=item["classification"],
                confidence_level=item["confidence"],
                verification_required=item["verification_required"],
                recommendation=item["recommendation"],
                reason=item["reason"],
                sha256_exact_duplicate=item["sha256_exact_duplicate"],
                rank=item["rank"]
            )
            db.add(db_record)
        db.commit()

        # Emit event-driven notifications for meaningful matches
        meaningful_matches = [
            r for r in raw_results
            if r.get("classification") in ["Exact Duplicate", "Very Strong Visual Match", "Strong Visual Match"]
        ]
        if meaningful_matches:
            top_match = meaningful_matches[0]
            case_obj = db.query(Case).filter(Case.id == case_id).first()
            if case_obj:
                cbir_recipients = [uid for uid in [case_obj.investigator_id, case_obj.cyber_expert_id] if uid]
                for rec_id in cbir_recipients:
                    create_notification(
                        db=db,
                        title="CBIR Match Detected",
                        message=(
                            f"Significant visual match ({top_match['classification']}, "
                            f"{round(top_match['visual_similarity_score'] * 100, 1)}%) "
                            f"detected in case {case_obj.case_id} for evidence '{top_match['query_filename']}'."
                        ),
                        notification_type="CBIR_MATCH_ALERT",
                        user_id=rec_id,
                        cyber_cell_id=None
                    )
    except Exception as e:
        db.rollback()
        # Non-blocking persistence failure
        print(f"Warning: Failed to persist CBIR results to TiDB: {e}")

    # 9. Apply server-side filters if requested
    filtered_results = raw_results
    if req.classification and req.classification.strip() not in ("All", ""):
        target_cls = req.classification.strip().lower()
        filtered_results = [r for r in filtered_results if r["classification"].lower() == target_cls]

    if req.min_visual_similarity and req.min_visual_similarity > 0.0:
        filtered_results = [r for r in filtered_results if r["visual_similarity_score"] >= req.min_visual_similarity]

    if req.top_k is not None and req.top_k > 0:
        filtered_results = filtered_results[:req.top_k]

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
            verification_required=r["verification_required"],
            recommendation=r["recommendation"],
            reason=r["reason"],
            rank=r["rank"]
        )
        for r in filtered_results
    ]

    summary = CBIRSearchSummary(
        total_same_case_images=total_same_case,
        candidates_analyzed=candidates_count,
        query_excluded_id=str(query_ev.evidence_id),
        result_count=len(result_models)
    )

    return CBIRCompareResponse(
        case_id=case_id,
        query_evidence_id=str(query_ev.evidence_id),
        query_filename=query_ev.file_name,
        summary=summary,
        results=result_models,
        forensic_disclaimer=FORENSIC_DISCLAIMER
    )


def get_stored_cbir_results(
    case_id: int,
    query_evidence_id: Optional[int],
    db: Session
) -> CBIRCompareResponse:
    """
    Retrieve previously persisted CBIR comparison results from TiDB Cloud.
    """
    query = db.query(CBIRResult).filter(CBIRResult.case_id == case_id)
    if query_evidence_id:
        query = query.filter(CBIRResult.query_evidence_id == query_evidence_id)

    db_rows = query.order_by(CBIRResult.rank.asc()).all()

    if not db_rows:
        return CBIRCompareResponse(
            case_id=case_id,
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

    # Fetch evidence details
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
                case_id=r.case_id,
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
                verification_required=r.verification_required,
                recommendation=r.recommendation,
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
        case_id=case_id,
        query_evidence_id=q_str,
        query_filename=q_fn,
        summary=summary,
        results=results,
        forensic_disclaimer=FORENSIC_DISCLAIMER
    )


def get_cbir_candidate_detail(
    case_id: int,
    candidate_evidence_id: int,
    query_evidence_id: Optional[int],
    db: Session
) -> CBIRCandidateDetailResponse:
    """
    Get detailed breakdown for a single candidate image for the View Result Details modal.
    """
    query = db.query(CBIRResult).filter(
        CBIRResult.case_id == case_id,
        CBIRResult.candidate_evidence_id == candidate_evidence_id
    )
    if query_evidence_id:
        query = query.filter(CBIRResult.query_evidence_id == query_evidence_id)

    record = query.first()
    if not record:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Candidate comparison record not found for evidence {candidate_evidence_id}."
        )

    q_ev = db.query(Evidence).filter(Evidence.id == record.query_evidence_id).first()
    c_ev = db.query(Evidence).filter(Evidence.id == record.candidate_evidence_id).first()

    cand_result = CBIRCandidateResult(
        case_id=record.case_id,
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
        verification_required=record.verification_required,
        recommendation=record.recommendation,
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
