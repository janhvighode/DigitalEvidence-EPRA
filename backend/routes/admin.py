from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from services.admin_service import (
    get_pending_registrations,
    reject_registration,
    approve_registration
)
router = APIRouter(
    prefix="/admin",
    tags=["Admin"]
)


@router.get("/pending-registrations")
def fetch_pending_registrations(
    db: Session = Depends(get_db)
):
    return get_pending_registrations(db)

@router.put("/reject/{registration_id}")
def reject_registration_request(
    registration_id: int,
    db: Session = Depends(get_db)
):
    return reject_registration(
        db,
        registration_id
    )

@router.put("/approve/{registration_id}")
def approve_registration_request(
    registration_id: int,
    db: Session = Depends(get_db)
):
    return approve_registration(
        db,
        registration_id
    )