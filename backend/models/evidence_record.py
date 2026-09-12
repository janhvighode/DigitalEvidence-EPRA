from sqlalchemy import Column, Integer, String, BigInteger, Boolean, DateTime, UniqueConstraint
from sqlalchemy.sql import func
from database.database import Base


class EvidenceRecord(Base):
    __tablename__ = "evidence_records"
    __table_args__ = (
        UniqueConstraint("case_id", "external_evidence_id", name="uq_case_external_evidence"),
    )

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    external_evidence_id = Column(String(100), nullable=True, index=True)
    external_source = Column(String(100), default="shared_backend", nullable=True)
    case_id = Column(String(100), nullable=False, index=True)
    original_filename = Column(String(255), nullable=False)
    stored_filename = Column(String(255), nullable=False)
    file_path = Column(String(512), nullable=False)  # Internal controlled reference; NEVER in public schemas
    file_extension = Column(String(50))
    mime_type = Column(String(150))
    mime_type_source = Column(String(100), nullable=True)  # "backend_supplied", "extension_guessed", "unspecified"
    evidence_type = Column(String(50))
    file_size_bytes = Column(BigInteger, default=0)

    # Explicitly labeled filesystem timestamps with sources
    filesystem_ctime = Column(String(50), nullable=True)
    filesystem_ctime_source = Column(String(100), nullable=True)
    filesystem_mtime = Column(String(50), nullable=True)
    filesystem_mtime_source = Column(String(100), nullable=True)

    # Genuine metadata timestamps with provenance
    created_at = Column(DateTime(timezone=True), nullable=True)
    created_at_source = Column(String(100), nullable=True)
    modified_at = Column(DateTime(timezone=True), nullable=True)
    modified_at_source = Column(String(100), nullable=True)
    accessed_at = Column(DateTime(timezone=True), nullable=True)
    accessed_at_source = Column(String(100), nullable=True)

    # Upload timestamp and investigator (missing remains None)
    uploaded_at = Column(DateTime(timezone=True), nullable=True)
    investigator_id = Column(String(100), nullable=True)
    investigator_name = Column(String(150), nullable=True)

    is_empty_file = Column(Boolean, default=False)
    processing_status = Column(String(50), default="PROCESSED")
    notes = Column(String(500), nullable=True)

    # Existing hash values and verification results supplied by the backend
    # Passed through by Member 5, NEVER recalculated locally
    original_sha256 = Column(String(64), nullable=True)
    current_sha256 = Column(String(64), nullable=True)
    verification_status = Column(String(50), nullable=True)  # "Verified", "Tampered", "Pending", "Unknown", "Error"
    verification_timestamp = Column(DateTime(timezone=True), nullable=True)
    verification_source = Column(String(100), nullable=True)
    verification_notes = Column(String(500), nullable=True)
    retrieved_at = Column(DateTime(timezone=True), nullable=True)
    cached_at = Column(DateTime(timezone=True), nullable=True)
