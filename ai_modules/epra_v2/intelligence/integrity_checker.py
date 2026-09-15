"""
integrity_checker.py

Calculates Authenticity Risk (AR)

Formula:
AR = (HR + CCR + IR + CR) / 4

HR  -> Hash Risk (Calculated here)
CCR -> Chain Risk (Received)
IR  -> Integrity Risk (Received)
CR  -> Consistency Risk (Received)
"""

import hashlib
from pathlib import Path

from .chain_risk_analyzer import ChainRiskAnalyzer
from .integrity_risk_analyzer import IntegrityRiskAnalyzer
from .consistency_risk_analyzer import ConsistencyRiskAnalyzer


class IntegrityChecker:

    @staticmethod
    def generate_hash(file_path: str) -> str:
        """
        Generate SHA-256 hash of a file.
        """
        if not file_path or not Path(file_path).is_file():
            return ""

        sha256 = hashlib.sha256()

        with open(file_path, "rb") as file:
            while chunk := file.read(4096):
                sha256.update(chunk)

        return sha256.hexdigest()

    @staticmethod
    def verify_hash(generated_hash: str, stored_hash: str) -> bool:
        """
        Compare generated hash with stored hash.
        Requires both hashes to be non-empty.
        """
        if not generated_hash or not stored_hash:
            return False

        return generated_hash == stored_hash

    @staticmethod
    def calculate_hash_risk(hash_verified: bool) -> float:
        """
        HR

        Hash Match     -> 0
        Hash Mismatch  -> 1
        """

        return 0.0 if hash_verified else 1.0

    @staticmethod
    def calculate_authenticity_risk(
        hash_risk: float,
        chain_risk: float,
        integrity_risk: float,
        consistency_risk: float
    ) -> float:
        """
        AR = (HR + CCR + IR + CR) / 4
        """

        return round(
            (
                hash_risk
                + chain_risk
                + integrity_risk
                + consistency_risk
            ) / 4,
            4
        )

    @classmethod
    def process(cls, evidence):
        """
        Complete Authenticity Risk pipeline.
        Consumes Member 5 forensic facts and calculates AR = (HR + CCR + IR + CR) / 4.
        """
        if not hasattr(evidence, "pending_external_inputs"):
            evidence.pending_external_inputs = {}

        # Track missing Member 5 reference facts
        if not getattr(evidence, "stored_hash", ""):
            evidence.pending_external_inputs["AR_STORED_HASH"] = (
                "MISSING EXTERNAL INPUT / INTEGRATION PENDING (Member 5 — Reference Hash)"
            )

        if not getattr(evidence.metadata, "chain_of_custody", None):
            evidence.pending_external_inputs["AR_CHAIN_OF_CUSTODY"] = (
                "MISSING EXTERNAL INPUT / INTEGRATION PENDING (Member 5 — Chain of Custody)"
            )

        generated_hash = cls.generate_hash(
            evidence.metadata.absolute_path
        )
        if not generated_hash and getattr(evidence, "generated_hash", ""):
            generated_hash = evidence.generated_hash

        hash_verified = cls.verify_hash(
            generated_hash,
            evidence.stored_hash
        )

        hash_risk = cls.calculate_hash_risk(
            hash_verified
        )

        # Dynamically calculate CCR if chain of custody is present or not yet set
        if not getattr(evidence, "chain_risk", 0.0) or getattr(evidence.metadata, "chain_of_custody", None):
            ChainRiskAnalyzer.process(evidence)

        # Dynamically calculate IR if not manually set
        if not getattr(evidence, "integrity_risk", 0.0):
            IntegrityRiskAnalyzer.process(evidence)

        # Dynamically calculate CR if not manually set
        if not getattr(evidence, "consistency_risk", 0.0):
            ConsistencyRiskAnalyzer.process(evidence)

        authenticity_risk = cls.calculate_authenticity_risk(
            hash_risk,
            evidence.chain_risk,
            evidence.integrity_risk,
            evidence.consistency_risk
        )

        # Store results

        evidence.generated_hash = generated_hash
        evidence.hash_verified = hash_verified
        evidence.hash_risk = hash_risk
        evidence.authenticity_risk = authenticity_risk

        return evidence