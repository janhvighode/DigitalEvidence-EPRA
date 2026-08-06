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


class IntegrityChecker:

    @staticmethod
    def generate_hash(file_path: str) -> str:
        """
        Generate SHA-256 hash of a file.
        """

        sha256 = hashlib.sha256()

        with open(file_path, "rb") as file:
            while chunk := file.read(4096):
                sha256.update(chunk)

        return sha256.hexdigest()

    @staticmethod
    def verify_hash(generated_hash: str, stored_hash: str) -> bool:
        """
        Compare generated hash with stored hash.
        """

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
    def process(cls,evidence):
        """
        Complete Authenticity Risk pipeline.
        """

        generated_hash = cls.generate_hash(
            evidence.metadata.absolute_path
        )

        hash_verified = cls.verify_hash(
            generated_hash,
            evidence.stored_hash
        )

        hash_risk = cls.calculate_hash_risk(
            hash_verified
        )

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