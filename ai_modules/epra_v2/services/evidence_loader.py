"""
evidence_loader.py

Loads evidence from different sources.

Supports:

1. Local File
2. Imported Metadata
"""

from ..models.evidence import Evidence

from ..intelligence.metadata_extractor import MetadataExtractor
from ..intelligence.metadata_importer import MetadataImporter


class EvidenceLoader:

    """
    Creates Evidence objects.
    """

    @staticmethod
    def load_from_file(file_path: str):

        metadata = MetadataExtractor.extract(
            file_path
        )

        return Evidence(
            metadata=metadata
        )

    @staticmethod
    def load_from_metadata(json_path: str):

        metadata = MetadataImporter.import_json(
            json_path
        )

        return Evidence(
            metadata=metadata
        )