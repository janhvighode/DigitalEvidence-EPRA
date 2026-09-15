"""
chain_risk_analyzer.py

Calculates Chain of Custody Risk (CCR)
from forensic chain-of-custody metadata.
"""

from datetime import datetime


class ChainRiskAnalyzer:
    """
    Calculates chain-of-custody risk.
    """

    REQUIRED_FIELDS = {
        "officer",
        "role",
        "action",
        "time"
    }

    AUTHORIZED_ROLES = {
        "INVESTIGATOR",
        "CYBER_FORENSIC_EXPERT",
        "ADMINISTRATOR",
        "AUTHORIZED_LAB_PERSONNEL"
    }

    @staticmethod
    def calculate_availability_risk(chain_of_custody):

        if not chain_of_custody:
            return 1.0

        return 0.0

    @classmethod
    def calculate_completeness_risk(
        cls,
        chain_of_custody
    ):

        if not chain_of_custody:
            return 1.0

        total_fields = (
            len(chain_of_custody)
            * len(cls.REQUIRED_FIELDS)
        )

        missing_fields = 0

        for entry in chain_of_custody:

            for field in cls.REQUIRED_FIELDS:

                if (
                    field not in entry
                    or entry[field] in (None, "")
                ):
                    missing_fields += 1

        if total_fields == 0:
            return 1.0

        return round(
            missing_fields / total_fields,
            4
        )

    @staticmethod
    def calculate_chronology_risk(
        chain_of_custody
    ):

        if not chain_of_custody:
            return 1.0

        timestamps = []

        for entry in chain_of_custody:

            time_value = entry.get("time")

            if not time_value:
                continue

            try:

                timestamps.append(
                    datetime.fromisoformat(
                        str(time_value)
                    )
                )

            except ValueError:

                return 1.0

        if len(timestamps) <= 1:
            return 0.0

        for index in range(
            1,
            len(timestamps)
        ):

            if (
                timestamps[index]
                < timestamps[index - 1]
            ):
                return 1.0

        return 0.0

    @classmethod
    def calculate_handler_risk(
        cls,
        chain_of_custody
    ):

        if not chain_of_custody:
            return 1.0

        total_handlers = 0
        unauthorized_handlers = 0

        for entry in chain_of_custody:

            role = entry.get("role")

            if not role:
                continue

            total_handlers += 1

            if (
                str(role).upper()
                not in cls.AUTHORIZED_ROLES
            ):
                unauthorized_handlers += 1

        if total_handlers == 0:
            return 1.0

        return round(
            unauthorized_handlers
            / total_handlers,
            4
        )

    @classmethod
    def calculate_chain_risk(
        cls,
        evidence
    ):

        chain_of_custody = (
            evidence.metadata.chain_of_custody
        )

        availability_risk = (
            cls.calculate_availability_risk(
                chain_of_custody
            )
        )

        completeness_risk = (
            cls.calculate_completeness_risk(
                chain_of_custody
            )
        )

        chronology_risk = (
            cls.calculate_chronology_risk(
                chain_of_custody
            )
        )

        handler_risk = (
            cls.calculate_handler_risk(
                chain_of_custody
            )
        )

        chain_risk = (
            availability_risk
            + completeness_risk
            + chronology_risk
            + handler_risk
        ) / 4

        return round(
            chain_risk,
            4
        )

    @classmethod
    def process(
        cls,
        evidence
    ):

        evidence.chain_risk = (
            cls.calculate_chain_risk(
                evidence
            )
        )

        return evidence