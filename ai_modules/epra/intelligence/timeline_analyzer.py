from datetime import datetime


class TimelineAnalyzer:
    """
    Calculates how recent a piece of evidence is.
    """

    def calculate_age(self, timestamp: str) -> int:
        """
        Returns age of evidence in days.
        """

        evidence_time = datetime.fromisoformat(timestamp)

        current_time = datetime.now()

        age = current_time - evidence_time

        return age.days

    def is_recent(self, timestamp: str, days: int = 30) -> bool:
        """
        Checks whether evidence is recent.
        """

        return self.calculate_age(timestamp) <= days