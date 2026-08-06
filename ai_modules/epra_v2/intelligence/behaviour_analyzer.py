"""
behaviour_analyzer.py

Calculates Behaviour Intelligence (BI)

Formula:
BI = (AF + RF + DF + PF) / 4

AF -> Access Frequency
RF -> Repetition Factor
DF -> Deletion Factor
PF -> Privilege Factor
"""


class BehaviourAnalyzer:
    """
    Calculates Behaviour Intelligence.
    """

    @staticmethod
    def calculate_behaviour_intelligence(
        access_frequency: float,
        repetition_factor: float,
        deletion_factor: float,
        privilege_factor: float
    ) -> float:
        """
        Calculates Behaviour Intelligence.

        All inputs must be normalized between 0 and 1.
        """

        score = (
            access_frequency +
            repetition_factor +
            deletion_factor +
            privilege_factor
        ) / 4

        return round(score, 4)

    @classmethod
    def process(cls, evidence):
        """
        Updates Behaviour Intelligence.

        Currently uses dummy values.
        Later these values will come from
        behavioural analysis modules.
        """

        # -----------------------------
        # Dummy Values (Temporary)
        # -----------------------------

        access_frequency = evidence.access_frequency

        repetition_factor = evidence.repetition_factor

        deletion_factor = evidence.deletion_factor

        privilege_factor = evidence.privilege_factor

        evidence.behaviour_intelligence = (
            cls.calculate_behaviour_intelligence(
                access_frequency,
                repetition_factor,
                deletion_factor,
                privilege_factor
            )
        )

        return evidence