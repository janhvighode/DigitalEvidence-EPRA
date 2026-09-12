from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.sql import func
from app.database import Base


class IntegrityVerificationLog(Base):
    __tablename__ = "integrity_logs"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    evidence_id = Column(Integer, ForeignKey("evidence_records.id"), nullable=False, index=True)
    case_id = Column(String(100), nullable=True, index=True)
    baseline_hash = Column(String(64), nullable=True)
    current_hash = Column(String(64), nullable=True)
    outcome = Column(String(50), nullable=False)  # MATCH, MISMATCH, NOT_VERIFIED, ERROR
    event_reference = Column(String(64), nullable=True, index=True)
    actor = Column(String(150), default="system")
    is_system_action = Column(Boolean, default=False, nullable=False)
    actor_is_unverified = Column(Boolean, default=True, nullable=False)
    error_reason = Column(String(500), nullable=True)
    verified_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
