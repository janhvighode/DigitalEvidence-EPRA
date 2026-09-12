from sqlalchemy import Column, Integer, String, DateTime, ForeignKey, Index
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship

from database.database import Base


class EvidenceLink(Base):
    """
    Relational evidence links adapted from Trisha's evidence_linker module.
    Persists explicit links between evidence items, suspect entities, and devices.
    """
    __tablename__ = "evidence_links"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)

    # Scoped to Case
    case_id = Column(
        Integer,
        ForeignKey("cases.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Linked Evidence
    evidence_id = Column(
        Integer,
        ForeignKey("evidences.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )

    # Associated Suspect display identity or entity identifier
    suspect_name = Column(String(255), nullable=True)

    # Associated Device hardware / serial / make / model
    device_name = Column(String(255), nullable=True)

    # Relationship type e.g., MANUAL_LINK, DEVICE_SOURCE, SUSPECT_POSSESSION
    relationship_type = Column(String(100), default="MANUAL_LINK", nullable=False)

    # Case notes / remarks
    notes = Column(String(500), nullable=True)

    # Creation timestamp
    created_at = Column(
        DateTime,
        server_default=func.now()
    )

    # ORM relationships
    case = relationship("Case")
    evidence = relationship("Evidence")
