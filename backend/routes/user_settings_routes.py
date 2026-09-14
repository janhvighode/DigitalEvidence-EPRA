"""
User Settings API Router.
Provides authenticated endpoints for:
- GET /settings (Fetch or auto-initialize preferences)
- PUT /settings (Update preferences)
- PUT /settings/change-password (Secure authenticated password change)

Supports Administrator, Investigator, and Cyber Expert roles.
"""
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user
from schemas.user_settings import (
    UserSettingsResponse,
    UserSettingsUpdate,
    ChangePasswordRequest,
    ChangePasswordResponse,
)
from services.user_settings_service import UserSettingsService


router = APIRouter(
    prefix="/settings",
    tags=["Settings"]
)


@router.get(
    "",
    response_model=UserSettingsResponse,
    summary="Get or initialize current user settings"
)
@router.get(
    "/",
    response_model=UserSettingsResponse,
    include_in_schema=False
)
def get_settings(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Fetch the authenticated user's settings.
    If no settings exist, provisions centralized defaults (LIGHT, true, true, 30 min)
    and returns the persisted record.
    """
    return UserSettingsService.get_or_create_settings(db, current_user)


@router.put(
    "",
    response_model=UserSettingsResponse,
    summary="Update current user settings"
)
@router.put(
    "/",
    response_model=UserSettingsResponse,
    include_in_schema=False
)
def update_settings(
    data: UserSettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Update theme, notification toggles, and auto-logout preferences for current_user.
    Validates theme ('LIGHT'|'DARK') and auto_logout_minutes (15|30|60|120|null).
    """
    return UserSettingsService.update_settings(db, current_user, data)


@router.put(
    "/change-password",
    response_model=ChangePasswordResponse,
    summary="Change password for current authenticated user"
)
@router.put(
    "/change-password/",
    response_model=ChangePasswordResponse,
    include_in_schema=False
)
def change_password(
    data: ChangePasswordRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Secure authenticated password change.
    Verifies current password, enforces password complexity policy,
    hashes the new password via bcrypt, clears is_first_login, and
    prompts frontend to require re-login.
    """
    return UserSettingsService.change_password(db, current_user, data)
