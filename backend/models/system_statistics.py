from sqlalchemy import Column, Integer, Float
from database.database import Base


class SystemStatistics(Base):
    __tablename__ = "system_statistics"

    id = Column(Integer, primary_key=True, index=True)

    total_evidence = Column(Integer, default=0)

    high_priority = Column(Integer, default=0)
    medium_priority = Column(Integer, default=0)
    low_priority = Column(Integer, default=0)
    pending_analysis = Column(Integer, default=0)

    average_epra_score = Column(Float, default=0.0)
    highest_score = Column(Float, default=0.0)
    lowest_score = Column(Float, default=0.0)

    total_cbir_images = Column(Integer, default=0)
    matched_images = Column(Integer, default=0)
    failed_matches = Column(Integer, default=0)