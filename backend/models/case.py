from sqlalchemy import Column, Integer, String, Text, Enum, ForeignKey, TIMESTAMP
from sqlalchemy.sql import func
from database.database import Base


class Case(Base):
    __tablename__ = "cases"

    id = Column(Integer, primary_key=True, index=True)

    case_id = Column(String(20), unique=True, nullable=False)

    title = Column(String(255), nullable=False)

    description = Column(Text)

    investigator_id = Column(Integer, ForeignKey("users.id"))

    priority = Column(
        Enum("Low", "Medium", "High", "Critical"),
        default="Medium"
    )

    status = Column(
    Enum(
        "Open",
        "In Progress",
        "Under Review",
        "Closed",
        name="case_status"
    ),
    default="Open"
)

    created_by = Column(Integer, ForeignKey("users.id"))

    created_at = Column(TIMESTAMP, server_default=func.now())

    updated_at = Column(
        TIMESTAMP,
        server_default=func.now(),
        onupdate=func.now()
    )