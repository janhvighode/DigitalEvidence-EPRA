from sqlalchemy import Column, String, DateTime
from sqlalchemy.sql import func
from database.database import Base


class CurrentCustodyInfo(Base):
    """
    Current custody state for an evidence item.
    Keyed to evidence_id (string to support external evidence identities).
    Holder, department, and status are nullable by default — NEVER invented!
    """
    __tablename__ = "current_custody_info"

    evidence_id = Column(String(100), primary_key=True, index=True)
    case_id = Column(String(100), nullable=False, index=True)

    # Nullable holder details - populated only from genuine recorded actions or transfers
    current_holder_id = Column(String(100), nullable=True)
    current_holder_name = Column(String(150), nullable=True)
    current_holder_role = Column(String(100), nullable=True)
    department = Column(String(150), nullable=True)

    assigned_on = Column(DateTime(timezone=True), nullable=True)
    last_accessed = Column(DateTime(timezone=True), nullable=True)
    location = Column(String(255), nullable=True)
    remarks = Column(String(500), nullable=True)

    # No hardcoded default status; null until determined by genuine action
    custody_status = Column(String(50), nullable=True)

    # Pending transfer recipient where applicable
    pending_recipient_id = Column(String(100), nullable=True)
    pending_recipient_name = Column(String(150), nullable=True)

    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
