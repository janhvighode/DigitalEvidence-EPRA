from sqlalchemy import Column, Integer, String, Float, Boolean, Text, DateTime, ForeignKey
from sqlalchemy.sql import func
from database.database import Base


class CBIRResult(Base):
    """
    CBIR Comparison Result Model.
    Persists case-scoped Content-Based Image Retrieval candidate comparisons in TiDB Cloud.
    """
    __tablename__ = "cbir_results"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    case_id = Column(
        Integer,
        ForeignKey("cases.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    query_evidence_id = Column(
        Integer,
        ForeignKey("evidences.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    candidate_evidence_id = Column(
        Integer,
        ForeignKey("evidences.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    visual_similarity_score = Column(Float, nullable=False)
    semantic_score = Column(Float, nullable=False)

    edge_similarity = Column(Float, nullable=False, default=0.0)
    orb_similarity = Column(Float, nullable=False, default=0.0)
    color_similarity = Column(Float, nullable=False, default=0.0)
    grayscale_similarity = Column(Float, nullable=False, default=0.0)

    classification = Column(String(100), nullable=False)
    confidence_level = Column(String(50), nullable=False)
    verification_required = Column(Boolean, nullable=False, default=True)
    recommendation = Column(String(100), nullable=False)
    reason = Column(Text, nullable=True)

    sha256_exact_duplicate = Column(Boolean, nullable=False, default=False)
    rank = Column(Integer, nullable=False, default=1)

    created_at = Column(DateTime, server_default=func.now())
