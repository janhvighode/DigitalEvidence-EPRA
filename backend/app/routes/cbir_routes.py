# ============================================================
# Digital Evidence EPRA
# Module : CBIR / Content-Based Image Retrieval
# File   : backend/app/routes/cbir_routes.py
# Purpose: FastAPI endpoints for CBIR evidence comparison
#          providing resilient schema handling, dynamic case evidence
#          fetching, and zero production hardcoding.
# Author : Member 3
# ============================================================

import os
import sys
from pathlib import Path
from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field, model_validator
from sqlalchemy.orm import Session

# Ensure project root, ai_modules, and backend are in sys.path
CURRENT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = CURRENT_DIR.parent.parent.parent
CBIR_DIR = PROJECT_ROOT / "ai_modules" / "cbir"
REL_DIR = PROJECT_ROOT / "ai_modules" / "relationship_graph"
BACKEND_APP_DIR = CURRENT_DIR.parent

for p in [str(PROJECT_ROOT), str(CBIR_DIR), str(REL_DIR), str(BACKEND_APP_DIR)]:
    if p not in sys.path:
        sys.path.insert(0, p)

from app.database import get_db
from app.models.evidence_record import EvidenceRecord
from app.services.backend_adapter import get_backend_adapter
from app.services.metadata_service import MetadataService
from app.services.timeline_service import TimelineService
from app.services.hash_manifest_service import validate_safe_id

# Member 3 CBIR Modules
from feature_database import get_case_evidence, get_evidence as get_cbir_evidence, insert_feature
from image_search import (
    search_similar_images,
    format_investigator_image_result,
    render_investigator_image_card
)
from similarity import compute_multi_signal_similarity, classify_match
from hash_verifier import are_exact_duplicates

router = APIRouter(
    tags=["CBIR - Content-Based Image Retrieval"]
)


# ============================================================
# REQUEST & RESPONSE SCHEMAS
# ============================================================

class CBIRCompareRequest(BaseModel):
    """
    Robust CBIR Comparison Request Schema.
    Accepts case_id and query_evidence_id, while also accepting common
    aliases such as evidence_id or image_id to prevent HTTP 422 errors.
    """
    case_id: Optional[str] = Field(None, description="Case identifier")
    query_evidence_id: Optional[str] = Field(None, description="Query evidence ID")
    evidence_id: Optional[str] = Field(None, description="Alias for query_evidence_id")
    image_id: Optional[str] = Field(None, description="Alias for query_evidence_id")
    top_k: Optional[int] = Field(5, description="Maximum number of candidates to return (applied post-ranking)")

    @model_validator(mode="before")
    @classmethod
    def resolve_aliases(cls, values: Any) -> Any:
        if isinstance(values, dict):
            # Resolve query_evidence_id from aliases
            q_id = (
                values.get("query_evidence_id")
                or values.get("evidence_id")
                or values.get("image_id")
            )
            if q_id:
                clean_q_id = str(q_id).strip()
                values["query_evidence_id"] = clean_q_id
                values["evidence_id"] = clean_q_id
            if values.get("case_id"):
                values["case_id"] = str(values["case_id"]).strip()
        return values

    @property
    def resolved_query_evidence_id(self) -> Optional[str]:
        val = self.query_evidence_id or self.evidence_id or self.image_id
        return str(val).strip() if val else None


class CandidateMatchResult(BaseModel):
    rank: int
    case_id: str
    query_evidence_id: str
    query_filename: str
    candidate_evidence_id: str
    candidate_filename: str
    visual_similarity_score: float
    semantic_score: float
    edge_similarity: float
    orb_similarity: float
    color_similarity: float
    grayscale_similarity: float
    sha256_exact_duplicate: bool
    classification: str
    confidence_level: str
    verification_required: bool
    investigation_recommendation: str
    reason: str


class CBIRCompareResponse(BaseModel):
    status: str
    message: str
    case_id: str
    query_evidence_id: str
    query_filename: str
    total_case_evidence: int
    eligible_image_count: int
    candidates_compared: int
    results: List[CandidateMatchResult]
    cards: List[Dict[str, Any]]
    forensic_notice: str


# ============================================================
# HELPER FUNCTIONS: DYNAMIC EVIDENCE RESOLUTION & IMAGE FILTER
# ============================================================

SUPPORTED_IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".bmp", ".webp", ".gif", ".tiff")


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
        "persons", "person", "vehicles", "weapons", "mobiles",
        "laptops", "documents"
    }
    if cat in image_categories:
        if ext in SUPPORTED_IMAGE_EXTENSIONS or not ext:
            return True

    return False


def fetch_case_evidence_dynamically(db: Session, case_id: str) -> List[Dict[str, Any]]:
    """
    Fetch the complete current evidence collection belonging to case_id from
    all available genuine backend sources:
    1. DEPS Backend / EvidenceRecord table in database
    2. Shared Backend Adapter
    3. CBIR feature database (database/images.db)

    Deduplicates records by evidence_id and preserves real metadata.
    Never uses a hardcoded candidate list.
    """
    clean_case_id = str(case_id).strip()
    evidence_by_id: Dict[str, Dict[str, Any]] = {}

    # 1. Sync from adapter if available
    try:
        MetadataService.sync_case_from_adapter(db, clean_case_id)
    except Exception:
        pass

    # 2. Fetch from DB EvidenceRecord
    try:
        db_records = db.query(EvidenceRecord).filter(
            EvidenceRecord.case_id == clean_case_id
        ).all()

        for r in db_records:
            ev_id = r.external_evidence_id or str(r.id)
            evidence_by_id[ev_id] = {
                "evidence_id": ev_id,
                "case_id": r.case_id,
                "original_filename": r.original_filename,
                "filename": r.original_filename,
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

    # 3. Fetch from CBIR feature_database (SQLite images.db)
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
                    "case_id": clean_case_id,
                    "original_filename": fn,
                    "filename": fn,
                    "file_path": img_p,
                    "image_path": img_p,
                    "file_extension": Path(img_p).suffix.lower() if img_p else "",
                    "mime_type": f"image/{Path(img_p).suffix.lstrip('.').lower()}" if img_p else None,
                    "evidence_type": "Image",
                    "category": c.get("category", "General"),
                    "sha256_hash": c.get("sha256_hash"),
                    "feature_path": c.get("feature_path", ""),
                    "created_at": c.get("created_at"),
                    "description": c.get("description", "")
                }
            else:
                # Merge CBIR feature data into existing record
                if img_p and not evidence_by_id[ev_id].get("image_path"):
                    evidence_by_id[ev_id]["image_path"] = img_p
                    evidence_by_id[ev_id]["file_path"] = img_p
                if c.get("feature_path"):
                    evidence_by_id[ev_id]["feature_path"] = c.get("feature_path")
                if c.get("sha256_hash") and not evidence_by_id[ev_id].get("sha256_hash"):
                    evidence_by_id[ev_id]["sha256_hash"] = c.get("sha256_hash")
    except Exception:
        pass

    return list(evidence_by_id.values())


# ============================================================
# CORE CBIR COMPARISON LOGIC
# ============================================================

def execute_cbir_comparison(
    case_id: str,
    query_evidence_id: str,
    top_k: Optional[int] = 5,
    db: Optional[Session] = None
) -> Dict[str, Any]:
    """
    Execute dynamic CBIR comparison:
    1. Validate case and query evidence ID.
    2. Dynamically fetch all evidence items for case.
    3. Resolve query evidence record.
    4. Verify query evidence is an eligible image.
    5. Filter all eligible image candidates in the same case.
    6. Exclude query evidence itself (Self-Match Exclusion).
    7. Compare query against EVERY remaining eligible image candidate.
    8. Deterministically rank the complete comparison set.
    9. Apply top_k slicing only after ranking.
    10. Return clean, investigator-safe result payload.
    """
    clean_case_id = str(case_id).strip()
    clean_query_id = str(query_evidence_id).strip()

    # 1. Fetch complete case evidence dynamically
    all_case_evidence = fetch_case_evidence_dynamically(db, clean_case_id) if db else []
    if not all_case_evidence:
        # Fallback to feature_database directly if db is None
        try:
            all_case_evidence = get_case_evidence(clean_case_id)
        except Exception:
            all_case_evidence = []

    # 2. Resolve query evidence
    query_evidence = None
    for ev in all_case_evidence:
        ev_id = str(ev.get("evidence_id", ""))
        if ev_id == clean_query_id or ev.get("original_filename") == clean_query_id:
            query_evidence = ev
            break

    if not query_evidence:
        # Check if the query evidence belongs to another case
        other_case_found = False
        if db:
            try:
                rec = db.query(EvidenceRecord).filter(
                    (EvidenceRecord.external_evidence_id == clean_query_id) |
                    (EvidenceRecord.id == clean_query_id if clean_query_id.isdigit() else False)
                ).first()
                if rec and str(rec.case_id).strip() != clean_case_id:
                    other_case_found = True
            except Exception:
                pass

        if other_case_found:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Selected evidence does not belong to this case."
            )

        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Selected evidence was not found."
        )

    # 3. Verify query evidence is an eligible image
    query_fn = query_evidence.get("original_filename") or query_evidence.get("filename") or clean_query_id
    query_mime = query_evidence.get("mime_type")
    query_ext = query_evidence.get("file_extension") or Path(query_fn).suffix
    query_cat = query_evidence.get("category") or query_evidence.get("evidence_type")

    if not is_eligible_image_evidence(query_mime, query_ext, query_cat, query_fn):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="CBIR comparison is available only for image evidence."
        )

    query_img_path = query_evidence.get("image_path") or query_evidence.get("file_path")
    if not query_img_path or not os.path.isfile(query_img_path):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Evidence image file not found on disk: {query_fn}"
        )

    # 4. Dynamically identify ALL eligible image candidates from SAME case
    eligible_candidates = []
    for ev in all_case_evidence:
        ev_id = str(ev.get("evidence_id", ""))
        # Exclude query evidence itself
        if ev_id == clean_query_id:
            continue

        ev_img_p = ev.get("image_path") or ev.get("file_path")
        if not ev_img_p or not os.path.isfile(ev_img_p):
            continue

        # Check self-match by file path
        try:
            if os.path.abspath(ev_img_p) == os.path.abspath(query_img_path):
                continue
        except Exception:
            if ev_img_p == query_img_path:
                continue

        # Verify eligible image candidate
        c_fn = ev.get("original_filename") or ev.get("filename") or ev_id
        c_mime = ev.get("mime_type")
        c_ext = ev.get("file_extension") or Path(c_fn).suffix
        c_cat = ev.get("category") or ev.get("evidence_type")

        if is_eligible_image_evidence(c_mime, c_ext, c_cat, c_fn):
            eligible_candidates.append(ev)

    total_case_evidence_count = len(all_case_evidence)
    total_eligible_images = len(eligible_candidates) + 1  # query + candidates

    # 5. Handle zero candidates gracefully
    if not eligible_candidates:
        return {
            "status": "no_candidates",
            "message": "No other eligible image evidence is available in this case for comparison.",
            "case_id": clean_case_id,
            "query_evidence_id": clean_query_id,
            "query_filename": query_fn,
            "total_case_evidence": total_case_evidence_count,
            "eligible_image_count": 1,
            "candidates_compared": 0,
            "results": [],
            "cards": [],
            "forensic_notice": (
                "CBIR results represent visual comparison assistance only. "
                "Similarity does not establish identity, common source, authenticity, "
                "or criminal association. Investigator verification is required."
            )
        }

    # 6. Run comparison against EVERY remaining eligible image candidate (N - 1)
    raw_ranked_results = search_similar_images(
        query_image_path=query_img_path,
        case_evidence=eligible_candidates,
        top_k=None,  # Compare ALL candidates first before slicing
        case_id=clean_case_id,
        query_evidence_id=clean_query_id
    )

    candidates_compared = len(raw_ranked_results)

    # 7. Apply Top-K ONLY AFTER complete comparison and deterministic ranking
    k_limit = int(top_k) if (top_k is not None and int(top_k) > 0) else len(raw_ranked_results)
    sliced_results = raw_ranked_results[:k_limit]

    # 8. Build structured, sanitized response items and investigator display cards
    formatted_results = []
    investigator_cards = []

    for item in sliced_results:
        c_id = str(item.get("candidate_evidence_id", item.get("evidence_id", "")))
        c_fn = str(item.get("candidate_filename", item.get("filename_or_name", c_id)))

        match_res = {
            "rank": item.get("rank", 1),
            "case_id": clean_case_id,
            "query_evidence_id": clean_query_id,
            "query_filename": query_fn,
            "candidate_evidence_id": c_id,
            "candidate_filename": c_fn,
            "visual_similarity_score": float(item.get("visual_similarity_score", item.get("similarity", 0.0))),
            "semantic_score": float(item.get("semantic_score", 0.0)),
            "edge_similarity": float(item.get("edge_similarity", 0.0)),
            "orb_similarity": float(item.get("orb_similarity", 0.0)),
            "color_similarity": float(item.get("color_similarity", 0.0)),
            "grayscale_similarity": float(item.get("grayscale_similarity", 0.0)),
            "sha256_exact_duplicate": bool(item.get("sha256_exact_duplicate", False)),
            "classification": str(item.get("classification", "No Significant Visual Match")),
            "confidence_level": str(item.get("confidence_level", "Low")),
            "verification_required": bool(item.get("verification_required", True)),
            "investigation_recommendation": str(item.get("investigation_recommendation", "REVIEW_MANUALLY")),
            "reason": str(item.get("reason", ""))
        }
        formatted_results.append(match_res)

        # Generate clutter-free card with zero raw SHA or system paths
        card_data = format_investigator_image_result(item)
        if card_data:
            investigator_cards.append(card_data)

    # Optional timeline audit log
    if db:
        try:
            TimelineService.create_event(
                db=db,
                case_id=clean_case_id,
                action="CBIR Comparison Executed",
                details=f"CBIR comparison run for query #{clean_query_id} against {candidates_compared} candidates."
            )
        except Exception:
            pass

    return {
        "status": "Success",
        "message": f"CBIR comparison completed against {candidates_compared} eligible candidates.",
        "case_id": clean_case_id,
        "query_evidence_id": clean_query_id,
        "query_filename": query_fn,
        "total_case_evidence": total_case_evidence_count,
        "eligible_image_count": total_eligible_images,
        "candidates_compared": candidates_compared,
        "results": formatted_results,
        "cards": investigator_cards,
        "forensic_notice": (
            "CBIR results represent visual comparison assistance only. "
            "Similarity does not establish identity, common source, authenticity, "
            "or criminal association. Investigator verification is required."
        )
    }


# ============================================================
# API ENDPOINTS
# ============================================================

@router.post(
    "/cbir/compare",
    response_model=CBIRCompareResponse,
    status_code=status.HTTP_200_OK,
    summary="Run CBIR comparison for an evidence item within a case"
)
def compare_cbir_evidence(
    payload: CBIRCompareRequest,
    db: Session = Depends(get_db)
):
    """
    Primary CBIR comparison endpoint:
    - Accepts JSON payload with case_id and query_evidence_id (or evidence_id / image_id alias).
    - Resolves query evidence from database records.
    - Dynamically compares against ALL eligible image evidence in the SAME case (N - 1).
    - Deterministically ranks results and applies top_k slicing post-ranking.
    """
    case_id = payload.case_id
    query_id = payload.resolved_query_evidence_id

    if not case_id or not query_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Both 'case_id' and query evidence identifier ('query_evidence_id' or 'evidence_id') are required."
        )

    return execute_cbir_comparison(
        case_id=case_id,
        query_evidence_id=query_id,
        top_k=payload.top_k,
        db=db
    )


@router.post(
    "/cases/{case_id}/cbir/compare",
    response_model=CBIRCompareResponse,
    status_code=status.HTTP_200_OK,
    summary="Run CBIR comparison for a case-scoped endpoint"
)
def compare_case_cbir_evidence(
    case_id: str,
    payload: CBIRCompareRequest,
    db: Session = Depends(get_db)
):
    """
    Case-scoped CBIR comparison endpoint:
    Accepts case_id in URL path and query evidence identifier in JSON payload.
    """
    clean_case_id = validate_safe_id(case_id, "case_id")
    query_id = payload.resolved_query_evidence_id

    if not query_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Query evidence identifier ('query_evidence_id' or 'evidence_id') is required."
        )

    return execute_cbir_comparison(
        case_id=clean_case_id,
        query_evidence_id=query_id,
        top_k=payload.top_k,
        db=db
    )


@router.post(
    "/evidence/{evidence_id}/compare",
    response_model=CBIRCompareResponse,
    status_code=status.HTTP_200_OK,
    summary="Run CBIR comparison for an evidence-scoped endpoint"
)
def compare_single_evidence(
    evidence_id: str,
    case_id: Optional[str] = Query(None, description="Case ID if not in body"),
    payload: Optional[CBIRCompareRequest] = None,
    db: Session = Depends(get_db)
):
    """
    Evidence-scoped CBIR comparison endpoint:
    Accepts evidence_id in URL path and case_id in query or body.
    """
    clean_ev_id = str(evidence_id).strip()
    target_case_id = (payload.case_id if payload and payload.case_id else case_id)

    if not target_case_id:
        # Try resolving case_id from the evidence record itself
        rec = db.query(EvidenceRecord).filter(
            (EvidenceRecord.external_evidence_id == clean_ev_id) |
            (EvidenceRecord.id == clean_ev_id if clean_ev_id.isdigit() else False)
        ).first()
        if rec:
            target_case_id = rec.case_id

    if not target_case_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="case_id is required to perform case-isolated CBIR comparison."
        )

    clean_case_id = validate_safe_id(target_case_id, "case_id")
    top_k = payload.top_k if payload else 5

    return execute_cbir_comparison(
        case_id=clean_case_id,
        query_evidence_id=clean_ev_id,
        top_k=top_k,
        db=db
    )


@router.get(
    "/cases/{case_id}/cbir/eligible-images",
    status_code=status.HTTP_200_OK,
    summary="List all eligible image evidence items in a case available for CBIR comparison"
)
def get_case_eligible_images(
    case_id: str,
    db: Session = Depends(get_db)
):
    """
    Returns the list of evidence items in the case that are eligible for CBIR visual comparison.
    Filters out non-image evidence (PDF, TXT, Audio, Video, etc.).
    """
    clean_case_id = validate_safe_id(case_id, "case_id")
    all_evidence = fetch_case_evidence_dynamically(db, clean_case_id)

    eligible = []
    for ev in all_evidence:
        ev_id = str(ev.get("evidence_id", ""))
        fn = ev.get("original_filename") or ev.get("filename") or ev_id
        mime = ev.get("mime_type")
        ext = ev.get("file_extension") or Path(fn).suffix
        cat = ev.get("category") or ev.get("evidence_type")

        if is_eligible_image_evidence(mime, ext, cat, fn):
            eligible.append({
                "evidence_id": ev_id,
                "filename": fn,
                "category": cat or "Image",
                "mime_type": mime
            })

    return {
        "case_id": clean_case_id,
        "total_case_evidence": len(all_evidence),
        "eligible_image_count": len(eligible),
        "eligible_images": eligible
    }
