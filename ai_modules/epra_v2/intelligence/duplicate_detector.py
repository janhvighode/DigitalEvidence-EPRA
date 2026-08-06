"""
duplicate_detector.py

Detects duplicate digital evidence.
"""

from typing import List


class DuplicateDetector:
    """
    Detect duplicate evidence using SHA-256 hash.
    """

    @staticmethod
    def find_duplicate(current_evidence, evidence_database: List):
        """
        Parameters
        ----------
        current_evidence : Evidence

        evidence_database : list[Evidence]

        Returns
        -------
        tuple(bool, str)

        (is_duplicate, original_evidence_id)
        """

        current_hash = current_evidence.generated_hash

        for evidence in evidence_database:

            if evidence.generated_hash == current_hash:

                return (
                    True,
                    evidence.metadata.evidence_id
                )

        return (
            False,
            None
        )

    @classmethod
    def process(cls, current_evidence, evidence_database):

        is_duplicate, original_id = cls.find_duplicate(
            current_evidence,
            evidence_database
        )

        current_evidence.is_duplicate = is_duplicate
        current_evidence.original_evidence_id = original_id

        return current_evidence