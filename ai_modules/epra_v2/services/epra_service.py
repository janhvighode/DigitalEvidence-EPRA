"""
epra_service.py

Main orchestration service for EPRA V2.
Runs the complete evidence processing pipeline.
"""

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


class EPRAService:
    """
    Executes complete EPRA pipeline.
    """

    @classmethod
    def process(cls, evidence, evidence_database):

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

        evidence = RelationshipAnalyzer.process(evidence)

        evidence = DuplicateDetector.process(evidence, evidence_database)

        evidence = InvestigationAnalyzer.process(evidence)

        evidence = BehaviourAnalyzer.process(evidence)

        evidence = SemanticAnalyzer.process(evidence)

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