from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.sql import func
from database.database import Base


class Evidence(Base):
    __tablename__ = "evidences"

    id = Column(Integer, primary_key=True, index=True)

    # Human-readable Evidence ID (e.g., EV-1024-001)
    evidence_id = Column(String(50), unique=True, nullable=False, index=True)

    # Numeric parent case foreign key
    case_id = Column(
        Integer,
        ForeignKey("cases.id"),
        nullable=False,
        index=True
    )

    file_name = Column(String(255), nullable=False)

    file_type = Column(String(100), nullable=False)

    file_size = Column(Integer, nullable=False)

    file_path = Column(String(500), nullable=False)

    status = Column(String(50), default="Active")

    created_at = Column(
        DateTime,
        server_default=func.now()
    )
