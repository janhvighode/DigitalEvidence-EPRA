from sqlalchemy import Column, Integer, String, Boolean, DateTime
from sqlalchemy.sql import func
from app.database import Base


class ActivityLog(Base):
    __tablename__ = "activity_logs"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    case_id = Column(String(100), nullable=True, index=True)
    evidence_id = Column(Integer, nullable=True, index=True)
    external_evidence_id = Column(String(100), nullable=True, index=True)
    external_source = Column(String(100), nullable=True, default="SHARED_BACKEND")
    actor_id = Column(String(100), nullable=True)
    investigator_name = Column(String(150), nullable=False)
    action = Column(String(100), nullable=True)
    activity = Column(String(255), nullable=False)
    outcome = Column(String(100), default="SUCCESS")
    details = Column(String(500), nullable=True)
    ip_address = Column(String(50), nullable=True)
    event_reference = Column(String(64), nullable=True, index=True)
    is_system_action = Column(Boolean, default=False, nullable=False)
    actor_is_unverified = Column(Boolean, default=True, nullable=False)
    timestamp = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)