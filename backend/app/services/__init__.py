"""
Backend app services package.
Extends __path__ to also load all services from backend/services.
"""
from pathlib import Path

backend_services_dir = Path(__file__).resolve().parent.parent.parent / "services"
if str(backend_services_dir) not in __path__:
    __path__.append(str(backend_services_dir))

from services.hash_service import HashService
from services.file_hash_service import FileHashService

__all__ = ["HashService", "FileHashService"]
