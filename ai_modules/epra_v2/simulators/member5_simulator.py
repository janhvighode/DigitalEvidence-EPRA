"""
member5_simulator.py

Temporary simulator for Member 5.

This module provides dummy forensic metadata until the
actual forensic acquisition module is integrated.

Later this file will be replaced completely by
Member 5's implementation.
"""

from datetime import datetime


class Member5Simulator:

    @staticmethod
    def process(evidence):

        # ---------------------------------
        # Integrity
        # ---------------------------------

        evidence.stored_hash = evidence.generated_hash

        evidence.chain_risk = 0.20

        evidence.integrity_risk = 0.10

        evidence.consistency_risk = 0.15

        # ---------------------------------
        # Collection Information
        # ---------------------------------

        evidence.metadata.collection_device = "Seized Laptop"

        evidence.metadata.collected_by = "Investigator A"

        evidence.metadata.collection_time = datetime.now()

        evidence.metadata.evidence_source = "Laptop"

        evidence.metadata.acquisition_method = "Disk Imaging"

        # ---------------------------------
        # Access Information
        # ---------------------------------

        evidence.metadata.last_accessed_by = "Rahul"

        evidence.metadata.device_name = "DESKTOP-01"

        evidence.metadata.access_action = "OPEN"

        evidence.metadata.access_source = "Windows Event Log"

        evidence.metadata.access_count = 14

        evidence.metadata.access_timeline = [

            "2026-08-01 10:12",

            "2026-08-01 11:35",

            "2026-08-02 08:40"

        ]

        # ---------------------------------
        # Chain of Custody
        # ---------------------------------

        evidence.metadata.chain_of_custody = [

            {

                "officer": "Inspector A",

                "action": "Collected",

                "time": "2026-08-01 09:00"

            },

            {

                "officer": "Forensic Lab",

                "action": "Verified",

                "time": "2026-08-01 14:15"

            }

        ]

        return evidence