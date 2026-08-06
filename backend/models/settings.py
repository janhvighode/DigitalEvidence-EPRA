from sqlalchemy import Column, Integer, Boolean

from database.database import Base


class Settings(Base):

    __tablename__ = "settings"

    id = Column(Integer, primary_key=True, index=True)

    user_id = Column(Integer, unique=True, nullable=False)

    email_notifications = Column(Boolean, default=True)

    browser_notifications = Column(Boolean, default=True)

    auto_logout = Column(Integer, default=30)