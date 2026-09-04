from app.services.evidence_validation_service import (
    EvidenceValidationService
)
from app.services.evidence_classifier import EvidenceClassifier
from app.services.metadata_service import MetadataService
from app.services.hash_service import HashService


class EvidenceProcessingService:

    @staticmethod
    def process_evidence(
        evidence_id: int,
        file_path: str
    ) -> dict:
        """
        Complete processing pipeline for one evidence file.
        """

        # Step 1: Validate
        validation = EvidenceValidationService.validate_file(
            file_path
        )

        if not validation["valid"]:
            return {
                "success": False,
                "evidence_id": evidence_id,
                "validation": validation
            }

        # Step 2: Classification
        classification = EvidenceClassifier.classify(
            file_path
        )

        # Step 3: Metadata
        metadata = MetadataService.extract_metadata(
            file_path
        )

        # Step 4: SHA-256
        hash_record = HashService.generate_file_hash_record(
            evidence_id=evidence_id,
            file_path=file_path
        )

        return {
            "success": True,
            "evidence_id": evidence_id,
            "validation": validation,
            "classification": classification,
            "metadata": metadata,
            "hash": hash_record
        }