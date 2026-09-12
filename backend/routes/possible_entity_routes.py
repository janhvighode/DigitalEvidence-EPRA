from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.possible_entity import (
    RankedEntityResponse,
    EntityDetailResponse,
    EntitySummaryOverview,
    ProcessEntitiesResponse,
)
from services.epra_service import authorize_cyber_expert_case_access
from services.suspect_ranking_service import (
    process_case_suspect_ranking,
    get_case_ranked_possible_entities,
    get_case_possible_entities_summary,
    get_possible_entity_detail,
)

router = APIRouter(
    prefix="/cases",
    tags=["Possible Entities / Suspect Ranking"]
)


@router.post(
    "/{case_id}/possible-entities/process",
    response_model=ProcessEntitiesResponse,
    status_code=status.HTTP_200_OK,
    summary="Process and rank possible suspect entities for a case"
)
def process_possible_entities(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Triggers suspect/entity extraction, correlation, and ranking across all evidence
    in the case using Janhvi's EPRA V2 engine.
    - Idempotent and transaction-safe.
    - Resolves case by database ID or case code.
    - Enforces Cyber Expert authorization and assignment to the case.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)
    return process_case_suspect_ranking(db, case, current_user)


@router.get(
    "/{case_id}/possible-entities",
    response_model=List[RankedEntityResponse],
    status_code=status.HTTP_200_OK,
    summary="Get ranked possible entities for a case"
)
def get_ranked_possible_entities(
    case_id: str,
    limit: Optional[int] = Query(None, ge=1, description="Maximum number of entities to return"),
    entity_type: Optional[str] = Query(None, description="Filter by entity type (EMAIL, IP ADDRESS, CRYPTO WALLET, ACCOUNT ID, OTHER)"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Returns ranked possible entities for the case ordered by rank ascending.
    Rank 1 corresponds to the entity with the highest total EPRA score.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)
    return get_case_ranked_possible_entities(db, case, limit=limit, entity_type=entity_type)


@router.get(
    "/{case_id}/possible-entities/summary",
    response_model=EntitySummaryOverview,
    status_code=status.HTTP_200_OK,
    summary="Get possible entities summary for a case"
)
def get_possible_entities_summary(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Returns dynamic summary statistics of possible suspect entities for the case,
    including type distributions, score range, and top ranked entities.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)
    return get_case_possible_entities_summary(db, case)


@router.get(
    "/{case_id}/possible-entities/{entity_id}",
    response_model=EntityDetailResponse,
    status_code=status.HTTP_200_OK,
    summary="Get detailed view of a specific possible entity"
)
def get_possible_entity(
    case_id: str,
    entity_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Returns detailed entity information, including its full list of linked evidence items
    with their individual EPRA scores and priority levels.
    Accepts entity DB id, suspect_id (e.g., SUSPECT-8E3A4B5C), or display name.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)
    return get_possible_entity_detail(db, case, entity_id)
