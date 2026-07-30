from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from database.database import Base
from datetime import datetime


class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)

    full_name = Column(String(100), nullable=False)

    username = Column(String(100), unique=True, nullable=False)

    email = Column(String(150), unique=True, nullable=False)

    phone_number = Column(String(15), nullable=False)

    password = Column(String(255), nullable=False)

    role_id = Column(
        Integer,
        ForeignKey("roles.id"),
        nullable=False
    )

    cyber_cell_id = Column(
        Integer,
        ForeignKey("cyber_cells.id"),
        nullable=False
    )

    is_first_login = Column(
        Boolean,
        default=True
    )

    is_active = Column(
        Boolean,
        default=True
    )

    created_at = Column(
        DateTime,
        default=datetime.utcnow
    )