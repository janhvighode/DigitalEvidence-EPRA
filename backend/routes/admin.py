from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from models.user import User
from models.cyber_cell import CyberCell
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


def get_admin_city_id(
    db: Session,
    current_user: User
):
    cyber_cell = db.query(CyberCell).filter(
        CyberCell.id == current_user.cyber_cell_id
    ).first()

    if not cyber_cell:
        raise HTTPException(
            status_code=404,
            detail="Cyber Cell not found"
        )

    return cyber_cell.city_id


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

    city_id = get_admin_city_id(
        db,
        current_user
    )

    return get_pending_registrations(
        db,
        city_id
    )


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

    city_id = get_admin_city_id(
        db,
        current_user
    )

    return reject_registration(
        db,
        registration_id,
        city_id
    )


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

    city_id = get_admin_city_id(
        db,
        current_user
    )

    return approve_registration(
        db,
        registration_id,
        city_id
    )