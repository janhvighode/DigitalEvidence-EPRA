from sqlalchemy import Column, Integer, String
from database.database import Base


class City(Base):
    __tablename__ = "cities"

    id = Column(Integer, primary_key=True, index=True)

    city_name = Column(String(100), unique=True, nullable=False)