"""
relationship_analyzer.py

Extracts suspect entities from digital evidence.
"""

class RelationshipAnalyzer:

    @staticmethod
    def extract_entities(metadata):
        """
        Extract suspect related entities.

        Currently uses dummy data.

        Later this will be connected
        with NLP / Email / CBIR modules.
        """

        evidence_type = metadata.evidence_type

        if evidence_type == "EMAIL":

            return [
                "sender@example.com",
                "receiver@example.com"
            ]

        elif evidence_type == "DATABASE":

            return [
                "Rahul Sharma",
                "123456789"
            ]

        elif evidence_type == "DOCUMENT":

            return [
                "Rahul",
                "Amit"
            ]

        return []

    @classmethod
    def process(cls, evidence):

        evidence.related_entities = cls.extract_entities(
            evidence.metadata
        )

        return evidence