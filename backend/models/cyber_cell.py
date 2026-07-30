from sqlalchemy import Column, Integer, String, ForeignKey
from database.database import Base


class CyberCell(Base):
    __tablename__ = "cyber_cells"

    id = Column(Integer, primary_key=True, index=True)

    cyber_cell_name = Column(String(150), nullable=False)

    address = Column(String(255), nullable=True)

    admin_email = Column(String(150), nullable=False)

    city_id = Column(Integer, ForeignKey("cities.id"), nullable=False)