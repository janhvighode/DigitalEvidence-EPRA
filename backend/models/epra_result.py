from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, ForeignKey, JSON
from sqlalchemy.sql import func
from database.database import Base


class EPRAResult(Base):
    __tablename__ = "epra_results"

    id = Column(Integer, primary_key=True, index=True)

    case_id = Column(
        Integer,
        ForeignKey("cases.id"),
        nullable=False,
        index=True
    )

    evidence_id = Column(
        Integer,
        ForeignKey("evidences.id"),
        nullable=False,
        index=True
    )

    # Core EPRA Factors
    authenticity_risk = Column(Float, nullable=True)
    context_intelligence = Column(Float, nullable=True)
    behaviour_intelligence = Column(Float, nullable=True)
    semantic_intelligence = Column(Float, nullable=True)  # NULL when semantic_status is PENDING
    investigative_intelligence = Column(Float, nullable=True)

    # Semantic Status: "MEASURED" vs "PENDING"
    semantic_status = Column(String(50), default="PENDING", nullable=False)

    # Scoring and Priority
    ipi = Column(Float, nullable=True)
    epra_score = Column(Float, nullable=True)
    priority = Column(String(50), nullable=True)
    rank = Column(Integer, nullable=True)

    # Forensic and Duplicate Flags
    hash_verified = Column(Boolean, default=False)
    is_duplicate = Column(Boolean, default=False)

    # EPRA Analysis Status: "COMPLETE" vs "PARTIAL / PENDING INPUTS"
    analysis_status = Column(String(50), default="COMPLETE", nullable=False)

    # Pending external integration inputs list (JSON array of strings)
    pending_external_inputs = Column(JSON, nullable=True)

    created_at = Column(
        DateTime,
        server_default=func.now()
    )

    processed_at = Column(
        DateTime,
        server_default=func.now(),
        onupdate=func.now()
    )
