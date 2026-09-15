"""
evidence_ranker.py

Ranks evidence based on
EPRA Score.
"""


class EvidenceRanker:
    """
    Sorts evidence according to
    EPRA Score.
    """

    @staticmethod
    def rank(evidence_list):
        """
        Sorts evidence in descending
        order of EPRA Score.

        Highest score gets Rank 1.
        """

        ranked = sorted(
            evidence_list,
            key=lambda evidence: (
                -evidence.epra_score,
                evidence.metadata.file_name.lower()
            )
        )

        for index, evidence in enumerate(ranked, start=1):

            evidence.rank = index

        return ranked