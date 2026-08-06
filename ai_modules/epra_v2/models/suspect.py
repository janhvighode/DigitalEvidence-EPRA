"""
suspect.py

Defines the Suspect model used by the EPRA V2 engine.
"""

from dataclasses import dataclass, field

from .evidence import Evidence


@dataclass
class Suspect:
    """
    Represents a suspect identified from digital evidence.
    """

    suspect_id: str
    suspect_name: str

    evidence_list: list[Evidence] = field(default_factory=list)

    total_epra_score: float = 0.0

    rank: int = 0

    linked_evidence_ids: list[str] = field(default_factory=list)

    confidence_score: float = 0.0