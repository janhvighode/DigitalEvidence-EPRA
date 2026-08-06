from typing import List

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database.database import get_db

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


# ==========================
# KANBAN BOARD
# ==========================

@router.get("/board")
def fetch_case_board(
    db: Session = Depends(get_db)
):
    return get_case_board(db)


# ==========================
# CASE TIMELINE
# ==========================

@router.get(
    "/{case_id}/timeline",
    response_model=List[TimelineResponse]
)
def fetch_case_timeline(
    case_id: int,
    db: Session = Depends(get_db)
):
    return get_case_timeline(db, case_id)


# ==========================
# CASE DETAILS
# ==========================

@router.get("/{case_id}")
def fetch_case_details(
    case_id: int,
    db: Session = Depends(get_db)
):

    case = get_case_details(db, case_id)

    if not case:
        raise HTTPException(
            status_code=404,
            detail="Case not found"
        )

    return case


# ==========================
# ASSIGN INVESTIGATOR
# ==========================

@router.put(
    "/{case_id}/assign",
    response_model=AssignInvestigatorResponse
)
def assign_case(
    case_id: int,
    data: AssignInvestigatorRequest,
    db: Session = Depends(get_db)
):

    result = assign_investigator(
        db=db,
        case_id=case_id,
        investigator_id=data.investigator_id
    )

    if result is None:
        raise HTTPException(
            status_code=404,
            detail="Case not found"
        )

    if result == "INVESTIGATOR_NOT_FOUND":
        raise HTTPException(
            status_code=404,
            detail="Investigator not found"
        )

    return result