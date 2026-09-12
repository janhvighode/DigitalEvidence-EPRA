"""
epra_service.py

Main orchestration service for EPRA V2.
Runs the complete evidence processing pipeline.
"""

from typing import Optional
from ..intelligence.evidence_classifier import EvidenceClassifier
from ..intelligence.integrity_checker import IntegrityChecker
from ..intelligence.context_analyzer import ContextAnalyzer
from ..intelligence.relationship_analyzer import RelationshipAnalyzer
from ..intelligence.duplicate_detector import DuplicateDetector
from ..intelligence.investigation_analyzer import InvestigationAnalyzer
from ..intelligence.behaviour_analyzer import BehaviourAnalyzer
from ..intelligence.semantic_analyzer import SemanticAnalyzer
from ..intelligence.factor_collector import FactorCollector

from ..adm.weight_generator import WeightGenerator

from ..ranking.epra_engine import EPRAEngine
from ..ranking.priority_classifier import PriorityClassifier

from ..utils.validators import Validator
from ..utils.config import DEFAULT_DEMO_MODE


class EPRAService:
    """
    Executes complete EPRA pipeline.
    """

    @classmethod
    def process(
        cls,
        evidence,
        evidence_database,
        demo_mode: Optional[bool] = None,
        case_context: Optional[dict] = None
    ):
        """
        Runs the end-to-end EPRA pipeline on a single Evidence object.
        """
        if demo_mode is None:
            demo_mode = DEFAULT_DEMO_MODE

        Validator.validate_evidence(evidence)

        # -------------------------
        # Classification
        # -------------------------
        evidence = EvidenceClassifier.process(evidence)

        # -------------------------
        # Intelligence
        # -------------------------
        evidence = IntegrityChecker.process(evidence)

        evidence = ContextAnalyzer.process(evidence)

        evidence = RelationshipAnalyzer.process(evidence, demo_mode=demo_mode)

        evidence = DuplicateDetector.process(evidence, evidence_database)

        evidence = InvestigationAnalyzer.process(evidence)

        evidence = BehaviourAnalyzer.process(evidence, demo_mode=demo_mode)

        evidence = SemanticAnalyzer.process(
            evidence,
            demo_mode=demo_mode,
            case_context=case_context
        )

        # -------------------------
        # Collect Factors
        # -------------------------
        evidence = FactorCollector.process(evidence)

        # -------------------------
        # ADM
        # -------------------------
        evidence = WeightGenerator.process(evidence)

        # -------------------------
        # Mathematical Model
        # -------------------------
        evidence = EPRAEngine.process(evidence)

        # -------------------------
        # Priority
        # -------------------------
        evidence = PriorityClassifier.process(evidence)

        evidence.processed = True

        return evidence

    @classmethod
    def correlate_and_rank_suspects(
        cls,
        evidence_database: list,
        demo_mode: Optional[bool] = None
    ) -> list:
        """
        Extracts possible suspect candidates across all processed evidence in the database,
        aggregates their linked evidence EPRA scores, and ranks them.
        """
        from ..ranking.suspect_ranker import SuspectRanker

        if demo_mode is None:
            demo_mode = DEFAULT_DEMO_MODE

        suspects = RelationshipAnalyzer.generate_suspect_candidates(
            evidence_database,
            demo_mode=demo_mode
        )
        return SuspectRanker.rank(suspects)