from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from sqlalchemy.sql import func
from database.database import Base


class CaseStatusHistory(Base):
    __tablename__ = "case_status_history"

    id = Column(Integer, primary_key=True, index=True, autoincrement=True)
    case_id = Column(
        Integer,
        ForeignKey("cases.id", ondelete="CASCADE"),
        nullable=False,
        index=True
    )
    old_status = Column(String(50), nullable=False)
    new_status = Column(String(50), nullable=False)
    changed_by_user_id = Column(
        Integer,
        ForeignKey("users.id"),
        nullable=False
    )
    changed_by_role = Column(String(50), nullable=False)
    changed_at = Column(
        DateTime,
        server_default=func.now(),
        nullable=False
    )
    remark = Column(String(500), nullable=True)
