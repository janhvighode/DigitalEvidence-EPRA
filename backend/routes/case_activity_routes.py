from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database.database import get_db

from models.user import User
from utils.current_user import get_current_user

from services.case_activity_service import (
    get_case_board,
    get_case_details,
    assign_investigator
)

from services.timeline_read_service import (
    get_case_timeline
)

from schemas.case_activity import (
    AssignInvestigatorRequest,
    AssignInvestigatorResponse
)

from schemas.timeline import (
    TimelineResponse
)

router = APIRouter(
    prefix="/cases",
    tags=["Case Activity"]
)


# ==========================================
# KANBAN BOARD
# ==========================================

@router.get("/board")
def fetch_case_board(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    board = get_case_board(
        db,
        current_user
    )

    return board


# ==========================================
# CASE TIMELINE
# ==========================================

@router.get(
    "/{case_id}/timeline",
    response_model=List[TimelineResponse]
)
def fetch_case_timeline(
    case_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    # First verify user has access to this case
    case = get_case_details(
        db,
        case_id,
        current_user
    )

    if not case:
        raise HTTPException(
            status_code=404,
            detail="Case not found or access denied"
        )

    return get_case_timeline(
        db,
        case_id
    )


# ==========================================
# CASE DETAILS
# ==========================================

@router.get("/{case_id}")
def fetch_case_details(
    case_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    case = get_case_details(
        db,
        case_id,
        current_user
    )

    if not case:
        raise HTTPException(
            status_code=404,
            detail="Case not found or access denied"
        )

    return case


# ==========================================
# ASSIGN INVESTIGATOR
# ==========================================

@router.put(
    "/{case_id}/assign",
    response_model=AssignInvestigatorResponse
)
def assign_case(
    case_id: int,
    data: AssignInvestigatorRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    result = assign_investigator(
        db=db,
        case_id=case_id,
        investigator_id=data.investigator_id,
        current_user=current_user
    )

    if result == "FORBIDDEN":
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    if result is None:
        raise HTTPException(
            status_code=404,
            detail="Case not found for your branch"
        )

    if result == "INVESTIGATOR_NOT_FOUND":
        raise HTTPException(
            status_code=404,
            detail=(
                "Active Investigator not found "
                "in your branch"
            )
        )

    return result