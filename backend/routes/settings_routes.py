from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db

from services.settings_service import (
    get_settings,
    update_settings
)

from schemas.settings import (
    SettingsResponse,
    SettingsUpdate
)

router = APIRouter(
    prefix="/settings",
    tags=["Settings"]
)


# ==========================================
# View Settings
# ==========================================

@router.get(
    "/",
    response_model=SettingsResponse
)
def fetch_settings(
    db: Session = Depends(get_db)
):

    return get_settings(db)


# ==========================================
# Update Settings
# ==========================================

@router.put(
    "/",
    response_model=SettingsResponse
)
def edit_settings(
    data: SettingsUpdate,
    db: Session = Depends(get_db)
):

    return update_settings(db, data)