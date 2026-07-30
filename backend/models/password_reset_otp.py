from sqlalchemy import Column, Integer, String, DateTime
from database.database import Base
from datetime import datetime


class PasswordResetOTP(Base):

    __tablename__ = "password_reset_otps"

    id = Column(
        Integer,
        primary_key=True,
        index=True
    )

    email = Column(
        String(100),
        nullable=False
    )

    otp = Column(
        String(6),
        nullable=False
    )

    created_at = Column(
        DateTime,
        default=datetime.utcnow
    )

    expires_at = Column(
        DateTime,
        nullable=False
    )