from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.sql import func
from database.database import Base


class EvidenceHash(Base):
    __tablename__ = "evidence_hashes"

    id = Column(Integer, primary_key=True, index=True)

    evidence_id = Column(
        Integer,
        ForeignKey("evidences.id"),
        nullable=False,
        index=True
    )

    file_name = Column(String(255), nullable=False)

    # Member 5 compatible SHA-256 field
    sha256_hash = Column(String(64), nullable=False)

    # Current calculated SHA-256
    current_hash = Column(String(64), nullable=False)

    # Original/trusted reference SHA-256 (null if unknown or unprovided)
    original_hash = Column(String(64), nullable=True)

    # Integrity check results
    hash_match = Column(Boolean, nullable=True)

    tampered = Column(Boolean, nullable=True)

    integrity_status = Column(
        String(50),
        default="Unknown",
        nullable=False
    )

    verified_at = Column(DateTime, nullable=True)

    verified_by = Column(
        Integer,
        ForeignKey("users.id"),
        nullable=True
    )

    created_at = Column(
        DateTime,
        server_default=func.now()
    )
