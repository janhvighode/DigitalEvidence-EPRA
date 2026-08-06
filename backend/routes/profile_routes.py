from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from database.database import get_db

from services.profile_service import (
    get_profile,
    update_profile
)

from schemas.profile import (
    ProfileResponse,
    ProfileUpdate
)

router = APIRouter(
    prefix="/profile",
    tags=["Profile"]
)


# ==========================================
# View Profile
# ==========================================

@router.get(
    "/",
    response_model=ProfileResponse
)
def fetch_profile(
    db: Session = Depends(get_db)
):

    profile = get_profile(db)

    if profile is None:
        raise HTTPException(
            status_code=404,
            detail="Profile not found"
        )

    return profile


# ==========================================
# Update Profile
# ==========================================

@router.put(
    "/",
    response_model=ProfileResponse
)
def edit_profile(
    data: ProfileUpdate,
    db: Session = Depends(get_db)
):

    profile = update_profile(db, data)

    if profile is None:
        raise HTTPException(
            status_code=404,
            detail="Profile not found"
        )

    return profile