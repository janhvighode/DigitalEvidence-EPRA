"""
Pydantic Schemas for User Settings and Authenticated Password Changes.
Provides strict request/response validation for all roles (Admin, Investigator, Cyber Expert).
"""
from typing import Optional, Set
from pydantic import BaseModel, Field, field_validator


ALLOWED_THEMES: Set[str] = {"LIGHT", "DARK"}
ALLOWED_AUTO_LOGOUT_MINUTES: Set[Optional[int]] = {15, 30, 60, 120, None}


class UserSettingsResponse(BaseModel):
    """Persisted user settings response contract."""
    theme: str = Field(..., description="Active theme preference ('LIGHT' or 'DARK')")
    email_notifications: bool = Field(..., description="Whether transactional and system emails are enabled")
    browser_notifications: bool = Field(..., description="Whether desktop browser push notifications are enabled")
    auto_logout_minutes: Optional[int] = Field(
        ...,
        description="Inactivity timeout in minutes (15, 30, 60, 120, or null for Never)"
    )

    class Config:
        from_attributes = True


class UserSettingsUpdate(BaseModel):
    """Payload to update current user's preferences."""
    theme: str = Field(..., description="Theme mode: 'LIGHT' or 'DARK'")
    email_notifications: bool = Field(..., description="Email notification preference toggle")
    browser_notifications: bool = Field(..., description="Browser notification preference toggle")
    auto_logout_minutes: Optional[int] = Field(
        None,
        description="Inactivity timeout in minutes: 15, 30, 60, 120, or null (Never)"
    )

    @field_validator("theme")
    @classmethod
    def validate_theme(cls, v: str) -> str:
        if not v or not isinstance(v, str):
            raise ValueError("Theme must be a non-empty string.")
        normalized = v.strip().upper()
        if normalized not in ALLOWED_THEMES:
            raise ValueError(f"Invalid theme '{v}'. Allowed themes are: {sorted(list(ALLOWED_THEMES))}")
        return normalized

    @field_validator("auto_logout_minutes")
    @classmethod
    def validate_auto_logout(cls, v: Optional[int]) -> Optional[int]:
        if v not in ALLOWED_AUTO_LOGOUT_MINUTES:
            raise ValueError(
                f"Invalid auto_logout_minutes '{v}'. Allowed values are: 15, 30, 60, 120, or null (Never)."
            )
        return v


class ChangePasswordRequest(BaseModel):
    """Payload for authenticated change-password endpoint."""
    current_password: str = Field(..., description="Existing active password")
    new_password: str = Field(..., description="New password complying with 12+ character complexity policy")
    confirm_password: str = Field(..., description="Confirmation of new password")


class ChangePasswordResponse(BaseModel):
    """Response returned upon successful password update."""
    message: str
    require_relogin: bool = True
