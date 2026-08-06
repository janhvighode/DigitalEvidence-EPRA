from typing import List, Optional
from pydantic import BaseModel, Field


class Suspect(BaseModel):
    """
    Represents a suspect involved in an investigation.
    """

    # ==========================
    # Identification
    # ==========================
    suspect_id: str
    case_id: str

    # ==========================
    # Basic Information
    # ==========================
    name: str
    email: Optional[str] = None
    phone: Optional[str] = None

    # ==========================
    # Linked Evidence
    # ==========================
    linked_evidence: List[str] = Field(default_factory=list)

    # ==========================
    # EPRA Result
    # ==========================
    confidence_score: float = 0.0
    rank: Optional[int] = None