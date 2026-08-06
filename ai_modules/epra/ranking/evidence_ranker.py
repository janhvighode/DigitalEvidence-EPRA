class EvidenceRanker:
    """
    Ranks evidence based on EPRA score.
    """

    def rank(self, evidence_list):
        """
        Sorts evidence in descending order of EPRA score.

        Parameters
        ----------
        evidence_list : list

        Example:
        [
            {"id": 1, "score": 0.92},
            {"id": 2, "score": 0.63}
        ]
        """

        ranked = sorted(
            evidence_list,
            key=lambda evidence: evidence["score"],
            reverse=True
        )

        return ranked