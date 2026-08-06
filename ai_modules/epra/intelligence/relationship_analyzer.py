class RelationshipAnalyzer:
    """
    Analyzes relationships between two evidence items.
    """

    def are_related(self, evidence1: dict, evidence2: dict) -> bool:
        """
        Determines whether two evidence items are related.

        Relationship is established if:
        - Same hash
        OR
        - Same suspect_id
        """

        if evidence1.get("hash") == evidence2.get("hash"):
            return True

        if evidence1.get("suspect_id") == evidence2.get("suspect_id"):
            return True

        return False