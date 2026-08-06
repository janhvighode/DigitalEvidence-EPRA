"""
epra_result.py

Defines the final output produced by the EPRA engine.
"""

from dataclasses import dataclass


@dataclass
class EPRAResult:
    """
    Stores the final EPRA analysis result for one evidence item.
    """

    authenticity_risk: float = 0.0
    context_intelligence: float = 0.0
    behaviour_intelligence: float = 0.0
    semantic_intelligence: float = 0.0
    investigative_intelligence: float = 0.0

    authenticity_weight: float = 0.0
    context_weight: float = 0.0
    behaviour_weight: float = 0.0
    semantic_weight: float = 0.0
    investigative_weight: float = 0.0

    investigation_priority_index: float = 0.0

    epra_score: float = 0.0

    priority: str = ""