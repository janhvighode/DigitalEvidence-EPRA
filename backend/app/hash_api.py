"""
Digital Evidence EPRA - Hash API & CBIR Entry Point
Points directly to the canonical main backend application.
"""
import sys
import os

BACKEND_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
if sys.path[0] != BACKEND_DIR:
    if BACKEND_DIR in sys.path:
        sys.path.remove(BACKEND_DIR)
    sys.path.insert(0, BACKEND_DIR)

from app.database import init_db
from app.main import app

# Initialize database schema immediately on import for testing environments
init_db()

__all__ = ["app"]
