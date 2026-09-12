from sqlalchemy import Column, String, BigInteger, Boolean, DateTime
from sqlalchemy.sql import func
from app.database import Base


class ReportRecord(Base):
    __tablename__ = "report_records"

    id = Column(String(64), primary_key=True, index=True)  # Unique UUID report_id
    case_id = Column(String(100), nullable=False, index=True)
    case_title = Column(String(255), nullable=True)
    crime_type = Column(String(100), nullable=True)
    
    investigator_name = Column(String(150), nullable=False)
    generated_by_id = Column(String(100), nullable=True)
    generated_by_role = Column(String(100), nullable=True)
    
    report_type = Column(String(100), default="Comprehensive Forensic Report", nullable=False)
    file_format = Column(String(20), default="PDF", nullable=False)
    file_size_bytes = Column(BigInteger, default=0)
    
    file_path = Column(String(512), nullable=False)  # Internal safe reports storage path
    file_name = Column(String(255), nullable=False)
    selected_sections = Column(String(1000), nullable=True)  # Comma-separated list of selected sections
    
    is_draft = Column(Boolean, default=False, nullable=False)
    event_reference = Column(String(64), nullable=True, index=True)
    generated_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)
