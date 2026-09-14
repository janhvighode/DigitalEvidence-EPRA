"""
User Settings ORM Model.
Stores one-to-one user preferences: theme, notification channels, and inactivity timeout.
Persisted in TiDB Cloud under 'user_settings' table.
"""
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.sql import func
from database.database import Base


class UserSettings(Base):
    """
    User Settings table representing 1-to-1 persisted preferences for authenticated users.
    Supports Administrator, Investigator, and Cyber Expert roles.
    """
    __tablename__ = "user_settings"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True
    )

    # Theme preference: LIGHT / DARK
    theme = Column(String(20), default="LIGHT", nullable=False)

    # Notification preferences
    email_notifications = Column(Boolean, default=True, nullable=False)
    browser_notifications = Column(Boolean, default=True, nullable=False)

    # Auto logout timeout in minutes: 15, 30, 60, 120, or NULL (Never)
    auto_logout_minutes = Column(Integer, default=30, nullable=True)

    created_at = Column(
        DateTime,
        server_default=func.now(),
        nullable=False
    )
    updated_at = Column(
        DateTime,
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False
    )
