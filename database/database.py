"""
Compatibility bridge for any external callers expecting `database.database`.
Points to the authoritative `app.database` engine and Base.
"""
import sys
from pathlib import Path

# Add backend directory to sys.path if not present
backend_dir = Path(__file__).resolve().parent.parent / "backend"
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

try:
    from app.database import Base, engine, SessionLocal, get_db, init_db
except ImportError:
    try:
        from backend.app.database import Base, engine, SessionLocal, get_db, init_db
    except ImportError:
        from sqlalchemy.orm import declarative_base
        Base = declarative_base()
        engine = None
        SessionLocal = None
        get_db = None
        init_db = None

__all__ = ["Base", "engine", "SessionLocal", "get_db", "init_db"]
