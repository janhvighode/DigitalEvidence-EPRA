from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func

from database.database import Base


class ActivityLog(Base):
    __tablename__ = "activity_logs"

    id = Column(Integer, primary_key=True, index=True)

    investigator_name = Column(String(100), nullable=False)

    activity = Column(String(255), nullable=False)

    ip_address = Column(String(50))

    timestamp = Column(DateTime(timezone=True), server_default=func.now())