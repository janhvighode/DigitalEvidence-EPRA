"""
evidence.py

Defines the Evidence model used throughout the EPRA V2 engine.
"""

from dataclasses import dataclass, field

from .metadata import Metadata


@dataclass
class Evidence:
    """
    Represents a single piece of digital evidence as it moves through
    the EPRA pipeline.
    """

    # ---------------------------------------------------------
    # Metadata
    # ---------------------------------------------------------

    metadata: Metadata

    # ---------------------------------------------------------
    # Relationship Information
    # ---------------------------------------------------------

    related_entities: list = field(default_factory=list)

    # ---------------------------------------------------------
    # Behaviour Inputs (Member 2)
    # ---------------------------------------------------------

    access_frequency: float = 0.0
    repetition_factor: float = 0.0
    deletion_factor: float = 0.0
    privilege_factor: float = 0.0

    # ---------------------------------------------------------
    # Duplicate Information
    # ---------------------------------------------------------

    is_duplicate: bool = False
    original_evidence_id: str = ""

    # ---------------------------------------------------------
    # Hash Verification
    # ---------------------------------------------------------

    generated_hash: str = ""
    stored_hash: str = ""
    hash_verified: bool = False
    hash_risk: float = 0.0
    chain_risk: float = 0.0
    integrity_risk: float = 0.0
    consistency_risk: float = 0.0

    # ---------------------------------------------------------
    # Intelligence Dimensions
    # ---------------------------------------------------------

    authenticity_risk: float = 0.0
    context_intelligence: float = 0.0
    behaviour_intelligence: float = 0.0
    semantic_intelligence: float = 0.0
    investigative_intelligence: float = 0.0

    # ---------------------------------------------------------
    # Collected Intelligence Factors
    # ---------------------------------------------------------

    factors: dict = field(default_factory=dict)
    # ---------------------------------------------------------
    # Adaptive Decision Matrix Weights
    # ---------------------------------------------------------

    authenticity_weight: float = 0.0
    context_weight: float = 0.0
    behaviour_weight: float = 0.0
    semantic_weight: float = 0.0
    investigative_weight: float = 0.0

    # ---------------------------------------------------------
    # Final Results
    # ---------------------------------------------------------

    investigation_priority_index: float = 0.0
    epra_score: float = 0.0
    priority: str = ""

    # ---------------------------------------------------------
    # Investigation Ranking
    # ---------------------------------------------------------

    rank: int = 0       

    # ---------------------------------------------------------
    # Processing Status
    # ---------------------------------------------------------

    processed: bool = False