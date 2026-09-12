"""
member5_simulator.py

ISOLATED DEMO/TEST FIXTURE ONLY:
This module provides sample forensic metadata for offline standalone demonstration
and unit testing. It must NEVER be used in production.
Production forensic facts must be supplied by Member 5.
"""

from datetime import datetime
import hashlib


class Member5Simulator:
    """
    Simulates Member 5 forensic metadata strictly for offline demo/test runs.
    """

    @staticmethod
    def process(evidence):

        # ---------------------------------
        # Integrity / Acquisition
        # ---------------------------------

        # Compute pre-acquisition baseline hash
        sha256 = hashlib.sha256()
        with open(evidence.metadata.absolute_path, "rb") as f:
            while chunk := f.read(4096):
                sha256.update(chunk)

        # In forensic reality, phishing email was received without acquisition baseline
        if "phishing" in evidence.metadata.file_name.lower():
            evidence.stored_hash = ""
        else:
            evidence.stored_hash = sha256.hexdigest()

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

                "role": "INVESTIGATOR",

                "action": "Collected",

                "time": "2026-08-01 09:00"

            },

            {

                "officer": "Forensic Lab",

                "role": "CYBER_FORENSIC_EXPERT",

                "action": "Verified",

                "time": "2026-08-01 14:15"

            }

        ]

        return evidence