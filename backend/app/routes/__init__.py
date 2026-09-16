"""
Backend app routes package.
Extends __path__ to also load all routes from backend/routes.
"""
from pathlib import Path

backend_routes_dir = Path(__file__).resolve().parent.parent.parent / "routes"
if str(backend_routes_dir) not in __path__:
    __path__.append(str(backend_routes_dir))

from routes.cbir_routes import cbir_router

__all__ = ["cbir_router"]
