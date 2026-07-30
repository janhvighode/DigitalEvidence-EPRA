from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, declarative_base
from urllib.parse import quote_plus

from config.settings import (
    DB_HOST,
    DB_PORT,
    DB_NAME,
    DB_USER,
    DB_PASSWORD,
)

# Encode password to handle special characters like @, #, %, etc.
DATABASE_PASSWORD = quote_plus(DB_PASSWORD)

# MySQL Database URL
DATABASE_URL = (
    f"mysql+pymysql://{DB_USER}:{DATABASE_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"
)

# Create database engine
engine = create_engine(
    DATABASE_URL,
    echo=True
)

# Create session
SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)

# Base class for all database models
Base = declarative_base()

# Dependency to get database session
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()