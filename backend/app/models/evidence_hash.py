from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func
from app.database import Base


class EvidenceHash(Base):
    __tablename__ = "evidence_hashes"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    evidence_id = Column(Integer, ForeignKey("evidence_records.id"), unique=True, nullable=False, index=True)
    case_id = Column(String(100), nullable=True, index=True)
    file_name = Column(String(255), nullable=False)
    hash_algorithm = Column(String(50), default="SHA-256", nullable=False)
    sha256_hash = Column(String(64), nullable=False)  # Immutable baseline hash
    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    __table_args__ = (
        UniqueConstraint("evidence_id", name="uq_evidence_baseline_hash"),
    )