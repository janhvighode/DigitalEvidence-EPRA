"""
Database forwarding and initialization module for backend/app
Connects directly to the main database engine and SessionLocal.
"""
import sys
import os

BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if sys.path[0] != BACKEND_DIR:
    if BACKEND_DIR in sys.path:
        sys.path.remove(BACKEND_DIR)
    sys.path.insert(0, BACKEND_DIR)

from database.database import SessionLocal, engine, Base, get_db

def init_db():
    """Ensure all database tables are created."""
    Base.metadata.create_all(bind=engine)

__all__ = ["SessionLocal", "engine", "Base", "get_db", "init_db"]
