from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session

from database.database import get_db
from utils.jwt_handler import verify_access_token

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

security = HTTPBearer()


# ==========================================
# View Profile
# ==========================================

@router.get(
    "/",
    response_model=ProfileResponse
)
def fetch_profile(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
):

    payload = verify_access_token(credentials.credentials)

    if payload is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired token"
        )

    user_id = payload.get("user_id")

    if user_id is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid token"
        )

    profile = get_profile(db, user_id)

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
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
):

    payload = verify_access_token(credentials.credentials)

    if payload is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid or expired token"
        )

    user_id = payload.get("user_id")

    if user_id is None:
        raise HTTPException(
            status_code=401,
            detail="Invalid token"
        )

    profile = update_profile(
        db,
        user_id,
        data
    )

    if profile is None:
        raise HTTPException(
            status_code=404,
            detail="Profile not found"
        )

    return profile