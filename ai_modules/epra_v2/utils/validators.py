"""
Validation utilities.
"""

from .exceptions import InvalidEvidenceException


class Validator:

    @staticmethod
    def validate_evidence(evidence):

        if evidence is None:
            raise InvalidEvidenceException(
                "Evidence object cannot be None."
            )

        if evidence.metadata is None:
            raise InvalidEvidenceException(
                "Metadata missing."
            )

        return True