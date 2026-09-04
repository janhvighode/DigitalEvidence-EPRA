from sqlalchemy import Column, Integer, String, DateTime
from sqlalchemy.sql import func

from database.database import Base


class CustodyLog(Base):
    __tablename__ = "custody_logs"

    id = Column(Integer, primary_key=True, index=True)

    evidence_id = Column(Integer, nullable=False)

    investigator_name = Column(String(100), nullable=False)

    action = Column(String(100), nullable=False)

    remarks = Column(String(255))

    timestamp = Column(DateTime(timezone=True), server_default=func.now())