from sqlalchemy import Column, Integer, String, DateTime, ForeignKey
from database.database import Base
from datetime import datetime


class RegistrationRequest(Base):
    __tablename__ = "registration_requests"

    id = Column(Integer, primary_key=True, index=True)

    full_name = Column(String(100), nullable=False)

    email = Column(String(150), unique=True, nullable=False)

    phone_number = Column(String(15), nullable=False)

    requested_role_id = Column(
        Integer,
        ForeignKey("roles.id"),
        nullable=False
    )

    city_id = Column(
        Integer,
        ForeignKey("cities.id"),
        nullable=False
    )

    cyber_cell_id = Column(
        Integer,
        ForeignKey("cyber_cells.id"),
        nullable=False
    )

    status = Column(
        String(20),
        default="Pending"
    )

    created_at = Column(
        DateTime,
        default=datetime.utcnow
    )