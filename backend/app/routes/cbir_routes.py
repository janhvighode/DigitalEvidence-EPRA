"""
Forwarding router to canonical backend.routes.cbir_routes
"""
from backend.routes.cbir_routes import cbir_router as router
from backend.routes.cbir_routes import *

__all__ = ["router"]
