from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.sql import func

from database.database import Base


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)

    title = Column(String(255), nullable=False)

    message = Column(String(500), nullable=False)

    type = Column(String(50), nullable=False)

    is_read = Column(Boolean, default=False)

    created_at = Column(
        DateTime,
        server_default=func.now()
    )