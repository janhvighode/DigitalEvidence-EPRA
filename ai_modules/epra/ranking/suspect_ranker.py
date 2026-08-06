class SuspectRanker:
    """
    Calculates the final suspect score based on
    weighted evidence scores.

    Formula:
        Suspect Score = Σ(Evidence Score × Evidence Weight)
    """

    def calculate_score(self, evidence_list):
        """
        Calculates the weighted score for a suspect.

        Parameters
        ----------
        evidence_list : list

        Example:
        [
            {
                "score": 0.95,
                "weight": 0.40
            },
            {
                "score": 0.82,
                "weight": 0.20
            }
        ]

        Returns
        -------
        float
            Final suspect score.
        """

        # Handle empty evidence list
        if not evidence_list:
            return 0.0

        total_score = 0.0

        for evidence in evidence_list:
            score = evidence.get("score", 0.0)
            weight = evidence.get("weight", 0.0)

            total_score += score * weight

        return round(total_score, 4)