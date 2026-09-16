"""
Backend app models forwarding package.
Extends __path__ to also load all models from backend/models.
"""
from pathlib import Path

backend_models_dir = Path(__file__).resolve().parent.parent.parent / "models"
if str(backend_models_dir) not in __path__:
    __path__.append(str(backend_models_dir))

from models.evidence_record import EvidenceRecord

__all__ = ["EvidenceRecord"]
