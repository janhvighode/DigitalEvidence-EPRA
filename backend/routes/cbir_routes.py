from typing import Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.cbir import (
    CBIRImagesListResponse,
    CBIRCompareRequest,
    CBIRCompareResponse,
    CBIRCandidateDetailResponse
)

from services.cbir_service import (
    authorize_cyber_expert_case_access,
    get_case_image_evidence,
    run_cbir_comparison,
    get_stored_cbir_results,
    get_cbir_candidate_detail
)

cbir_router = APIRouter(
    prefix="/cases",
    tags=["CBIR Working"]
)


@cbir_router.get(
    "/{case_id}/cbir/images",
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


@cbir_router.post(
    "/{case_id}/cbir/compare",
    response_model=CBIRCompareResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute CBIR comparison for a selected query image against same-case images"
)
def execute_cbir_comparison(
    case_id: int,
    req: CBIRCompareRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Compare selected query image against all remaining same-case images using Trisha's
    multi-signal CBIR algorithms (Edge + ORB + Color + Grayscale) with SHA-256 exact-duplicate
    prioritization, self-match exclusion, and conservative forensic safeguards.
    """
    authorize_cyber_expert_case_access(case_id, current_user, db)
    return run_cbir_comparison(case_id, req, db)


@cbir_router.get(
    "/{case_id}/cbir/results",
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
    "/{case_id}/cbir/details/{candidate_evidence_id}",
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
