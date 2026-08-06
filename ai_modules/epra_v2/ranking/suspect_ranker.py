"""
suspect_ranker.py

Ranks suspects based on
linked evidence.
"""


class SuspectRanker:
    """
    Generates suspect ranking
    from ranked evidence.
    """

    @staticmethod
    def rank(suspects):

        for suspect in suspects:

            total_score = 0.0

            for evidence in suspect.evidence_list:

                total_score += evidence.epra_score

            suspect.total_epra_score = round(
                total_score,
                2
            )

        ranked = sorted(
            suspects,
            key=lambda suspect: (
                -suspect.total_epra_score,
                suspect.suspect_name.lower()
            )
        )

        for rank, suspect in enumerate(
            ranked,
            start=1
        ):

            suspect.rank = rank

        return ranked