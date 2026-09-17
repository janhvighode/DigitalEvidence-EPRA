from typing import Optional, List, Dict, Any
from pathlib import Path
from fastapi import APIRouter, Depends, Query, status, HTTPException
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from models.evidence_record import EvidenceRecord
from models.evidence import Evidence
from utils.current_user import get_current_user, get_optional_current_user

from schemas.cbir import (
    CBIRImagesListResponse,
    CBIRCompareRequest,
    CBIRCompareResponse,
    CBIRCandidateDetailResponse,
    CBIRCaseEligibleImagesResponse,
    CaseSearchRequest,
    CaseSearchResponse
)

from services.cbir_service import (
    authorize_cyber_expert_case_access,
    authorize_case_access,
    get_case_image_evidence,
    run_cbir_comparison,
    get_stored_cbir_results,
    get_cbir_candidate_detail,
    fetch_case_evidence_dynamically,
    is_eligible_image_evidence,
    search_case_text_service,
    search_case_context_service,
    search_case_unified_service
)

cbir_router = APIRouter(
    tags=["CBIR Working & Forensic Retrieval"]
)


# ============================================================
# PRIMARY CBIR COMPARISON ENDPOINT
# ============================================================

@cbir_router.post(
    "/cbir/compare",
    response_model=CBIRCompareResponse,
    status_code=status.HTTP_200_OK,
    summary="Run CBIR comparison for an evidence item within a case"
)
def compare_cbir_evidence(
    payload: CBIRCompareRequest,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
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

    authorize_case_access(db, case_id, current_user)

    return run_cbir_comparison(
        case_id=case_id,
        req=payload,
        db=db,
        current_user=current_user
    )


# ============================================================
# CASE-SCOPED CBIR COMPARISON ENDPOINT
# ============================================================

@cbir_router.post(
    "/cases/{case_id}/cbir/compare",
    response_model=CBIRCompareResponse,
    status_code=status.HTTP_200_OK,
    summary="Run CBIR comparison for a case-scoped endpoint"
)
def compare_case_cbir_evidence(
    case_id: str,
    payload: CBIRCompareRequest,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    """
    Case-scoped CBIR comparison endpoint:
    Accepts case_id in URL path and query evidence identifier in JSON payload.
    """
    clean_case_id = str(case_id).strip()
    authorize_case_access(db, clean_case_id, current_user)

    query_id = payload.resolved_query_evidence_id
    if not query_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Query evidence identifier ('query_evidence_id' or 'evidence_id') is required."
        )

    # Ensure payload has the path case_id
    payload.case_id = clean_case_id

    return run_cbir_comparison(
        case_id=clean_case_id,
        req=payload,
        db=db,
        current_user=current_user
    )


def execute_cbir_comparison(
    case_id: Any,
    req: Optional[CBIRCompareRequest] = None,
    db: Optional[Session] = None,
    current_user: Optional[User] = None,
    payload: Optional[CBIRCompareRequest] = None
):
    """
    Python wrapper allowing direct invocation using req or payload keywords.
    """
    actual_req = req or payload or CBIRCompareRequest()
    return compare_case_cbir_evidence(
        case_id=str(case_id),
        payload=actual_req,
        db=db,
        current_user=current_user
    )




# ============================================================
# EVIDENCE-SCOPED CBIR COMPARISON ENDPOINT
# ============================================================

@cbir_router.post(
    "/evidence/{evidence_id}/compare",
    response_model=CBIRCompareResponse,
    status_code=status.HTTP_200_OK,
    summary="Run CBIR comparison for an evidence-scoped endpoint"
)
def compare_single_evidence(
    evidence_id: str,
    case_id: Optional[str] = Query(None, description="Case ID if not in body"),
    payload: Optional[CBIRCompareRequest] = None,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    """
    Evidence-scoped CBIR comparison endpoint:
    Accepts evidence_id in URL path and case_id in query or body.
    """
    clean_ev_id = str(evidence_id).strip()
    target_case_id = payload.case_id if payload and payload.case_id else case_id

    if not target_case_id:
        # Try resolving case_id from the evidence record itself
        rec = db.query(EvidenceRecord).filter(
            (EvidenceRecord.external_evidence_id == clean_ev_id) |
            (EvidenceRecord.id == int(clean_ev_id) if clean_ev_id.isdigit() else False)
        ).first()
        if rec:
            target_case_id = rec.case_id
        else:
            ev_rec = db.query(Evidence).filter(
                (Evidence.evidence_id == clean_ev_id) |
                (Evidence.id == int(clean_ev_id) if clean_ev_id.isdigit() else False)
            ).first()
            if ev_rec:
                target_case_id = str(ev_rec.case_id)

    if not target_case_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="case_id is required to perform case-isolated CBIR comparison."
        )

    clean_case_id = str(target_case_id).strip()
    authorize_case_access(db, clean_case_id, current_user)

    top_k = payload.top_k if payload and payload.top_k else 5
    req = CBIRCompareRequest(
        case_id=clean_case_id,
        query_evidence_id=clean_ev_id,
        top_k=top_k
    )

    return run_cbir_comparison(
        case_id=clean_case_id,
        req=req,
        db=db,
        current_user=current_user
    )


# ============================================================
# ELIGIBLE IMAGES LIST ENDPOINT
# ============================================================

@cbir_router.get(
    "/cases/{case_id}/cbir/eligible-images",
    status_code=status.HTTP_200_OK,
    summary="List all eligible image evidence items in a case available for CBIR comparison"
)
def get_case_eligible_images(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    """
    Returns the list of evidence items in the case that are eligible for CBIR visual comparison.
    Filters out non-image evidence (PDF, TXT, Audio, Video, etc.).
    """
    clean_case_id = str(case_id).strip()
    authorize_case_access(db, clean_case_id, current_user)

    all_evidence = fetch_case_evidence_dynamically(db, clean_case_id)

    eligible = []
    for ev in all_evidence:
        ev_id = str(ev.get("evidence_id", ""))
        fn = ev.get("original_filename") or ev.get("file_name") or ev_id
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


# ============================================================
# EXISTING CBIR ENDPOINTS
# ============================================================

@cbir_router.get(
    "/cases/{case_id}/cbir/images",
    response_model=CBIRImagesListResponse,
    status_code=status.HTTP_200_OK,
    summary="List available genuine image evidence for query selection"
)
def list_case_images(
    case_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Fetch all genuine image evidence for the selected case.
    Populates the 'Select Query Image' dropdown or grid in the CBIR Working sidebar module.
    """
    authorize_cyber_expert_case_access(case_id, current_user, db)
    return get_case_image_evidence(case_id, db)


@cbir_router.get(
    "/cases/{case_id}/cbir/results",
    response_model=CBIRCompareResponse,
    status_code=status.HTTP_200_OK,
    summary="Retrieve latest persisted CBIR comparison results for the case"
)
def get_cbir_results(
    case_id: int,
    query_evidence_id: Optional[int] = Query(default=None, description="Optional filter by query evidence ID"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Retrieve previously saved CBIR comparison results from TiDB Cloud for this case.
    """
    authorize_cyber_expert_case_access(case_id, current_user, db)
    return get_stored_cbir_results(case_id, query_evidence_id, db)


@cbir_router.get(
    "/cases/{case_id}/cbir/details/{candidate_evidence_id}",
    response_model=CBIRCandidateDetailResponse,
    status_code=status.HTTP_200_OK,
    summary="Retrieve candidate comparison details for View Details modal"
)
def get_candidate_details(
    case_id: int,
    candidate_evidence_id: int,
    query_evidence_id: Optional[int] = Query(default=None, description="Optional query evidence ID context"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Retrieve detailed feature breakdown (Edge, ORB, Color, Grayscale signals and forensic explanation)
    for a specific candidate comparison.
    """
    authorize_cyber_expert_case_access(case_id, current_user, db)
    return get_cbir_candidate_detail(case_id, candidate_evidence_id, query_evidence_id, db)


# ============================================================
# TEXT SEARCH ENDPOINTS (POST + GET)
# ============================================================

@cbir_router.post(
    "/cases/{case_id}/cbir/search/text",
    response_model=CaseSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute case-level text evidence search"
)
@cbir_router.post(
    "/cbir/search/text",
    response_model=CaseSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute text search across case evidence"
)
def search_case_text(
    payload: CaseSearchRequest,
    case_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    target_case_id = case_id or payload.case_id
    if not target_case_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="case_id is required for case-isolated text search."
        )

    return search_case_text_service(
        db=db,
        case_id=target_case_id,
        query_text=payload.query_text or "",
        top_k=payload.top_k or 10,
        search_mode=payload.search_mode or "text",
        max_hops=payload.max_hops or 2,
        current_user=current_user
    )


@cbir_router.get(
    "/cases/{case_id}/cbir/search/text",
    response_model=CaseSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute case-level text evidence search (GET query)"
)
@cbir_router.get(
    "/cbir/search/text",
    response_model=CaseSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute text search across case evidence (GET query)"
)
def search_case_text_get(
    case_id: Optional[str] = None,
    query_text: str = Query(default="", description="Search query string"),
    top_k: int = Query(default=10, description="Max results"),
    search_mode: str = Query(default="text", description="Search mode: 'text', 'context', or 'all'"),
    max_hops: int = Query(default=2, description="Max hops for graph context traversal"),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    if not case_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="case_id is required for case-isolated text search."
        )

    return search_case_text_service(
        db=db,
        case_id=case_id,
        query_text=query_text,
        top_k=top_k,
        search_mode=search_mode,
        max_hops=max_hops,
        current_user=current_user
    )


# ============================================================
# CONTEXT SEARCH ENDPOINTS (POST + GET)
# ============================================================

@cbir_router.post(
    "/cases/{case_id}/cbir/search/context",
    response_model=CaseSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute case-level graph context evidence search"
)
@cbir_router.post(
    "/cbir/search/context",
    response_model=CaseSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute context search across case relationship graph"
)
def search_case_context(
    payload: CaseSearchRequest,
    case_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    target_case_id = case_id or payload.case_id
    if not target_case_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="case_id is required for case-isolated context search."
        )

    return search_case_context_service(
        db=db,
        case_id=target_case_id,
        query_text=payload.query_text or "",
        max_hops=payload.max_hops or 2,
        top_k=payload.top_k or 10,
        current_user=current_user
    )


@cbir_router.get(
    "/cases/{case_id}/cbir/search/context",
    response_model=CaseSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute case-level graph context evidence search (GET query)"
)
@cbir_router.get(
    "/cbir/search/context",
    response_model=CaseSearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute context search across case relationship graph (GET query)"
)
def search_case_context_get(
    case_id: Optional[str] = None,
    query_text: str = Query(default="", description="Search query string"),
    max_hops: int = Query(default=2, description="Max hops for graph context traversal"),
    top_k: int = Query(default=10, description="Max results"),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    if not case_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="case_id is required for case-isolated context search."
        )

    return search_case_context_service(
        db=db,
        case_id=case_id,
        query_text=query_text,
        max_hops=max_hops,
        top_k=top_k,
        current_user=current_user
    )


# ============================================================
# UNIFIED RETRIEVAL ENDPOINTS (POST + GET)
# ============================================================

@cbir_router.post(
    "/cases/{case_id}/cbir/search/unified",
    status_code=status.HTTP_200_OK,
    summary="Execute unified hybrid retrieval"
)
@cbir_router.post(
    "/cbir/search/unified",
    status_code=status.HTTP_200_OK,
    summary="Execute unified hybrid forensic search"
)
def search_case_unified(
    payload: CaseSearchRequest,
    case_id: Optional[str] = None,
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    target_case_id = case_id or payload.case_id
    if not target_case_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="case_id is required for unified retrieval."
        )

    return search_case_unified_service(
        db=db,
        case_id=target_case_id,
        query_type=payload.search_mode or "text",
        query_text=payload.query_text,
        query_evidence_id=payload.query_evidence_id,
        query_image_path=payload.query_image_path,
        top_k=payload.top_k or 10,
        current_user=current_user
    )


@cbir_router.get(
    "/cases/{case_id}/cbir/search/unified",
    status_code=status.HTTP_200_OK,
    summary="Execute unified hybrid retrieval (GET query)"
)
@cbir_router.get(
    "/cbir/search/unified",
    status_code=status.HTTP_200_OK,
    summary="Execute unified hybrid forensic search (GET query)"
)
def search_case_unified_get(
    case_id: Optional[str] = None,
    query_text: Optional[str] = Query(default="", description="Search query string"),
    search_mode: str = Query(default="text", description="Search mode: 'text', 'context', 'hybrid', 'image', 'case_search'"),
    top_k: int = Query(default=10, description="Max results"),
    query_evidence_id: Optional[str] = Query(default=None, description="Query evidence ID"),
    query_image_path: Optional[str] = Query(default=None, description="Query image path"),
    db: Session = Depends(get_db),
    current_user: Optional[User] = Depends(get_optional_current_user)
):
    if not case_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="case_id is required for unified retrieval."
        )

    return search_case_unified_service(
        db=db,
        case_id=case_id,
        query_type=search_mode or "text",
        query_text=query_text,
        query_evidence_id=query_evidence_id,
        query_image_path=query_image_path,
        top_k=top_k,
        current_user=current_user
    )
