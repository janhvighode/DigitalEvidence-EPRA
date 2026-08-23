from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from models.user import User
from utils.current_user import get_current_user
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


# ==========================================
# GET PENDING REGISTRATION REQUESTS
# ==========================================

@router.get("/pending-registrations")
def fetch_pending_registrations(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    if current_user.role_id != 1:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    return get_pending_registrations(
        db,
        current_user
    )


# ==========================================
# REJECT REGISTRATION
# ==========================================

@router.put("/reject/{registration_id}")
def reject_registration_request(
    registration_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    if current_user.role_id != 1:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    return reject_registration(
        db,
        registration_id,
        current_user
    )


# ==========================================
# APPROVE REGISTRATION
# ==========================================

@router.put("/approve/{registration_id}")
def approve_registration_request(
    registration_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):

    if current_user.role_id != 1:
        raise HTTPException(
            status_code=403,
            detail="Administrator access required"
        )

    return approve_registration(
        db,
        registration_id,
        current_user
    )