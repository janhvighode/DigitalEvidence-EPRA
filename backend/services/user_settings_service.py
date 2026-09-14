"""
User Settings Service.
Handles preference retrieval, automated default provisioning, preference mutations,
and authenticated password changes for Administrator, Investigator, and Cyber Expert roles.
"""
from typing import Optional
from sqlalchemy.orm import Session
from sqlalchemy.exc import IntegrityError
from passlib.context import CryptContext
from fastapi import HTTPException, status

from models.user import User
from models.user_settings import UserSettings
from schemas.user_settings import (
    UserSettingsResponse,
    UserSettingsUpdate,
    ChangePasswordRequest,
    ChangePasswordResponse,
)
from utils.password_validator import validate_password


# Centralized Defaults
DEFAULT_THEME = "LIGHT"
DEFAULT_EMAIL_NOTIFICATIONS = True
DEFAULT_BROWSER_NOTIFICATIONS = True
DEFAULT_AUTO_LOGOUT_MINUTES = 30

# Shared bcrypt CryptContext
pwd_context = CryptContext(
    schemes=["bcrypt"],
    deprecated="auto"
)


class UserSettingsService:
    """Canonical service for managing user preferences and security settings."""

    @staticmethod
    def get_or_create_settings(db: Session, current_user: User) -> UserSettings:
        """
        Retrieve persisted settings for current_user.
        If no record exists, automatically provisions and persists default settings.
        Protects against race conditions with unique constraint handling.
        """
        settings = (
            db.query(UserSettings)
            .filter(UserSettings.user_id == current_user.id)
            .first()
        )

        if settings is not None:
            return settings

        # Provision defaults
        new_settings = UserSettings(
            user_id=current_user.id,
            theme=DEFAULT_THEME,
            email_notifications=DEFAULT_EMAIL_NOTIFICATIONS,
            browser_notifications=DEFAULT_BROWSER_NOTIFICATIONS,
            auto_logout_minutes=DEFAULT_AUTO_LOGOUT_MINUTES
        )

        try:
            db.add(new_settings)
            db.commit()
            db.refresh(new_settings)
            return new_settings
        except IntegrityError:
            db.rollback()
            # In case of concurrent creation, retrieve the existing row
            existing = (
                db.query(UserSettings)
                .filter(UserSettings.user_id == current_user.id)
                .first()
            )
            if existing:
                return existing
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to initialize user settings."
            )

    @classmethod
    def update_settings(
        cls,
        db: Session,
        current_user: User,
        data: UserSettingsUpdate
    ) -> UserSettings:
        """
        Update settings belonging exclusively to current_user.
        """
        settings = cls.get_or_create_settings(db, current_user)

        settings.theme = data.theme
        settings.email_notifications = data.email_notifications
        settings.browser_notifications = data.browser_notifications
        settings.auto_logout_minutes = data.auto_logout_minutes

        db.commit()
        db.refresh(settings)
        return settings

    @staticmethod
    def change_password(
        db: Session,
        current_user: User,
        data: ChangePasswordRequest
    ) -> ChangePasswordResponse:
        """
        Change password for current authenticated user.
        Enforces:
        1. Current password verification.
        2. Confirmation match.
        3. Difference between old and new passwords.
        4. Password complexity policy (12+ chars, uppercase, lowercase, digit, special char).
        5. Bcrypt hashing and is_first_login clearing.
        6. Zero password/hash leaks in responses or logs.
        """
        # 1. Verify current password
        if not pwd_context.verify(data.current_password, current_user.password):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Current password is incorrect."
            )

        # 2. Verify confirmation match
        if data.new_password != data.confirm_password:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="New password and Confirm password do not match."
            )

        # 3. Disallow identical new password
        if data.current_password == data.new_password:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="New password cannot be the same as the current password."
            )

        # 4. Enforce system password complexity policy
        validation_error = validate_password(data.new_password)
        if validation_error:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=validation_error
            )

        # 5. Hash new password and update user
        current_user.password = pwd_context.hash(data.new_password)
        current_user.is_first_login = False

        db.commit()
        db.refresh(current_user)

        return ChangePasswordResponse(
            message="Password changed successfully. Please log in again with your new password.",
            require_relogin=True
        )
