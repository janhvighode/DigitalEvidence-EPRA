from sqlalchemy import Column, Integer, String, Float, DateTime, ForeignKey, UniqueConstraint
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from database.database import Base


class PossibleEntity(Base):
    __tablename__ = "possible_entities"
    __table_args__ = (
        UniqueConstraint("case_id", "suspect_id", name="uq_case_suspect"),
    )

    id = Column(Integer, primary_key=True, index=True)

    # Scoped to case
    case_id = Column(
        Integer,
        ForeignKey("cases.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Deterministic suspect identifier (e.g., SUSPECT-8E3A4B5C)
    suspect_id = Column(String(50), nullable=False, index=True)

    # Display identity / identifier (e.g., attacker@evil.com, 198.51.100.23)
    suspect_name = Column(String(255), nullable=False)

    # Normalized type: EMAIL, IP ADDRESS, CRYPTO WALLET, ACCOUNT ID, OTHER
    entity_type = Column(String(50), nullable=False)

    # Rank determined by total EPRA score DESC, tie-break suspect_name ASC
    rank = Column(Integer, nullable=False, index=True)

    # Sum of linked evidence EPRA scores
    total_epra_score = Column(Float, nullable=False, default=0.0)

    # Number of linked evidence files
    linked_evidence_count = Column(Integer, nullable=False, default=0)

    # Recurrence indicator (0.0 to 1.0) - does NOT affect ranking
    confidence_score = Column(Float, nullable=True)

    created_at = Column(
        DateTime,
        server_default=func.now()
    )

    processed_at = Column(
        DateTime,
        server_default=func.now(),
        onupdate=func.now()
    )

    # Relational source of truth for linked evidence
    evidence_links = relationship(
        "PossibleEntityEvidenceLink",
        back_populates="entity",
        cascade="all, delete-orphan"
    )


class PossibleEntityEvidenceLink(Base):
    __tablename__ = "possible_entity_evidence_links"
    __table_args__ = (
        UniqueConstraint("entity_id", "evidence_id", name="uq_entity_evidence"),
    )

    id = Column(Integer, primary_key=True, index=True)

    entity_id = Column(
        Integer,
        ForeignKey("possible_entities.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    evidence_id = Column(
        Integer,
        ForeignKey("evidences.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    created_at = Column(
        DateTime,
        server_default=func.now()
    )

    # Relationships
    entity = relationship("PossibleEntity", back_populates="evidence_links")
    evidence = relationship("Evidence")
