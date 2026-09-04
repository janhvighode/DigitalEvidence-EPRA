from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func

from database.database import Base


class EvidenceHash(Base):
    __tablename__ = "evidence_hashes"

    id = Column(Integer, primary_key=True, index=True)

    evidence_id = Column(Integer, nullable=False)

    file_name = Column(String(255), nullable=False)

    sha256_hash = Column(String(64), nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())