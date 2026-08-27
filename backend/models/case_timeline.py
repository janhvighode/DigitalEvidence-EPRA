from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.sql import func

from database.database import Base


class CaseTimeline(Base):
    __tablename__ = "case_timeline"

    id = Column(Integer, primary_key=True, index=True)

    case_id = Column(
        Integer,
        ForeignKey("cases.id"),
        nullable=False
    )

    event = Column(String(255), nullable=False)

    performed_by = Column(Integer)

    performed_by_role = Column(String(50))

    created_at = Column(
        DateTime,
        server_default=func.now()
    )