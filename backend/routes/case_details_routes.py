from typing import List
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.case_details import (
    CaseDetailsResponse,
    CaseNoteCreate,
    CaseNoteResponse
)
from services.evidence_service import authorize_case_access
from services.case_details_service import (
    get_aggregated_case_details,
    get_case_notes,
    create_case_note
)

router = APIRouter(
    prefix="/cases",
    tags=["Case Details & Notes"]
)


@router.get(
    "/{case_id}/details",
    response_model=CaseDetailsResponse,
    status_code=status.HTTP_200_OK,
    summary="Get aggregated Case Details for Cyber Expert / Assigned Users"
)
def fetch_case_details_aggregated(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Returns the complete data-driven Case Details response:
    - Basic Information (real DB fields, dynamic creator and investigator lookup)
    - Involved Entities (genuine PossibleEntity records or empty list)
    - Case Timeline (deduplicated audit trail and case timeline records)
    - Evidence Summary (12 canonical EPRA types and derived categories)
    - Case Notes (persistent database notes)

    Strictly enforces role-based and assigned-case authorization.
    """
    return get_aggregated_case_details(
        db=db,
        case_identifier=case_id,
        current_user=current_user
    )


@router.get(
    "/{case_id}/notes",
    response_model=List[CaseNoteResponse],
    status_code=status.HTTP_200_OK,
    summary="Get Case Notes"
)
def fetch_case_notes(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Returns all persistent case notes for the given case.
    Strict case isolation and authorization enforced.
    """
    case = authorize_case_access(db, case_id, current_user)
    return get_case_notes(db=db, case=case)


@router.post(
    "/{case_id}/notes",
    response_model=CaseNoteResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Add a Case Note"
)
def add_case_note(
    case_id: str,
    data: CaseNoteCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    """
    Creates and persists a new note for the case.
    - Author is strictly bound to current_user.id.
    - Blank / whitespace notes return 400 Bad Request.
    - Appends audit event to case timeline.
    """
    case = authorize_case_access(db, case_id, current_user)
    return create_case_note(
        db=db,
        case=case,
        content=data.content,
        current_user=current_user
    )
