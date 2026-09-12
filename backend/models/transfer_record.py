from sqlalchemy import Column, String, DateTime
from database.database import Base


class TransferRecord(Base):
    __tablename__ = "transfer_records"

    transfer_reference = Column(String(64), primary_key=True, index=True)  # UUID transfer token
    evidence_id = Column(String(100), nullable=False, index=True)
    case_id = Column(String(100), nullable=False, index=True)
    sender_id = Column(String(100), nullable=True)
    sender_name = Column(String(150), nullable=False)
    recipient_id = Column(String(100), nullable=True)
    recipient_name = Column(String(150), nullable=False)
    status = Column(String(50), default="PENDING_RECEIPT", nullable=False)  # PENDING_RECEIPT, COMPLETED, CANCELLED
    initiated_at = Column(DateTime(timezone=True), nullable=False)
    received_at = Column(DateTime(timezone=True), nullable=True)
    remarks = Column(String(500), nullable=True)
    receipt_remarks = Column(String(500), nullable=True)
