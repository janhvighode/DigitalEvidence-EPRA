from sqlalchemy import Column, Integer, String, Boolean, DateTime, UniqueConstraint
from sqlalchemy.sql import func
from app.database import Base


class CustodyLog(Base):
    """
    Custody log entry recording authentic chain of custody events.
    Includes external_event_id with a unique constraint for idempotent ingestion.
    """
    __tablename__ = "custody_logs"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    evidence_id = Column(String(100), nullable=False, index=True)
    case_id = Column(String(100), nullable=True, index=True)
    
    # Idempotent ingestion key
    external_event_id = Column(String(100), unique=True, nullable=True, index=True)
    
    # Display and categorization fields
    event_type = Column(String(50), nullable=True)  # ACQUISITION, UPLOAD, HASH_GENERATED, TRANSFER, ACCESS, REPORT, UPDATE
    title = Column(String(150), nullable=True)
    
    investigator_id = Column(String(100), nullable=True)
    investigator_name = Column(String(150), nullable=False)
    actor_role = Column(String(100), nullable=True)
    
    action = Column(String(100), nullable=False)
    result = Column(String(100), nullable=True, default="SUCCESS")
    remarks = Column(String(500), nullable=True)
    
    transfer_reference = Column(String(64), nullable=True, index=True)
    transfer_sender = Column(String(150), nullable=True)
    transfer_recipient = Column(String(150), nullable=True)
    
    event_reference = Column(String(64), nullable=True, index=True)
    source_reference = Column(String(100), nullable=True)
    related_reference = Column(String(64), nullable=True, index=True)
    
    is_system_action = Column(Boolean, default=False, nullable=False)
    actor_is_unverified = Column(Boolean, default=True, nullable=False)
    
    # Occurrence timestamp vs audit recorded_at timestamp
    timestamp = Column(DateTime(timezone=True), nullable=False)
    recorded_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        UniqueConstraint("external_event_id", name="uq_custody_external_event"),
    )