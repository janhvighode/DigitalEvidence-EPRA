"""
main.py

EPRA V2 Main Entry Point

Runs complete investigation pipeline.

Author : Janhvi Ghode
Project : Smart Digital Evidence Prioritization System
"""

from pathlib import Path
import traceback

from ai_modules.epra_v2.services.evidence_loader import EvidenceLoader
from ai_modules.epra_v2.services.epra_service import EPRAService

from ai_modules.epra_v2.intelligence.integrity_checker import IntegrityChecker

from ai_modules.epra_v2.ranking.evidence_ranker import EvidenceRanker
from ai_modules.epra_v2.ranking.suspect_ranker import SuspectRanker

from ai_modules.epra_v2.models.suspect import Suspect
print("Suspect Class :", Suspect)
print("Module :", Suspect.__module__)

from ai_modules.epra_v2.simulators.member5_simulator import Member5Simulator


# ==========================================================
# CONFIGURATION
# ==========================================================

EVIDENCE_FOLDER = Path(
    "ai_modules/epra_v2/demo/sample_evidence"
)

USE_FORENSIC_METADATA = False

FORENSIC_METADATA = Path(
    "demo/forensic_metadata/metadata.json"
)


# ==========================================================
# DATABASES
# ==========================================================

evidence_database = []

suspect_database = []


# ==========================================================
# HEADER
# ==========================================================

print("\n")
print("=" * 80)
print("EPRA V2 DIGITAL FORENSIC ENGINE")
print("=" * 80)
print()


# ==========================================================
# LOAD FILES
# ==========================================================

try:

    if USE_FORENSIC_METADATA:

        evidence = EvidenceLoader.load_from_metadata(
            str(FORENSIC_METADATA)
        )

        evidence_list = [
            evidence
        ]

    else:

        if not EVIDENCE_FOLDER.exists():

            raise FileNotFoundError(
                f"Folder not found : {EVIDENCE_FOLDER}"
            )

        evidence_list = []

        for file in EVIDENCE_FOLDER.iterdir():

            if file.is_file():

                evidence_list.append(

                    EvidenceLoader.load_from_file(

                        str(file)

                    )

                )

except Exception:

    traceback.print_exc()

    exit()


# ==========================================================
# PROCESS EACH EVIDENCE
# ==========================================================

for evidence in evidence_list:

    print("-" * 80)

    print("Processing")

    print(evidence.metadata.file_name)

    # ------------------------------------------------------
    # Member 5 Dummy
    # ------------------------------------------------------

    evidence.stored_hash = ""

    evidence.chain_risk = 0.20

    evidence.integrity_risk = 0.10

    evidence.consistency_risk = 0.15

    

    # ------------------------------------------------------
    # Member 3 Dummy
    # ------------------------------------------------------

    evidence.semantic_score = 0.82

    # ------------------------------------------------------
    # Member 2 Dummy
    # ------------------------------------------------------

    evidence.access_frequency = 0.70

    evidence.repetition_factor = 0.60

    evidence.deletion_factor = 0.20

    evidence.privilege_factor = 0.80

    evidence = EPRAService.process(
    evidence,
    evidence_database
    )

    # ------------------------------------------------------
    # EPRA Pipeline
    # ------------------------------------------------------

    evidence = EPRAService.process(

        evidence,

        evidence_database

    )

    evidence_database.append(

        evidence

    )

    # ------------------------------------------------------
    # Create Dummy Suspects
    # ------------------------------------------------------

    if len(evidence.related_entities) > 0:

        for entity in evidence.related_entities:

            found = None

            for suspect in suspect_database:

                if suspect.suspect_name == entity:

                    found = suspect

                    break

            if found is None:

                suspect = Suspect(

                    suspect_id=str(

                        len(suspect_database) + 1

                    ),

                    suspect_name=entity

                )

                print("========== SUSPECT OBJECT ==========")
                print(vars(suspect))
                print("====================================")

                suspect.evidence_list.append(

                    evidence

                )

                suspect.linked_evidence_ids.append(

                    evidence.metadata.evidence_id

                )

                suspect_database.append(

                    suspect

                )

            else:

                found.evidence_list.append(

                    evidence

                )

                found.linked_evidence_ids.append(

                    evidence.metadata.evidence_id

                )
                # ==========================================================
# EVIDENCE RANKING
# ==========================================================

print("\n")
print("=" * 80)
print("RANKING DIGITAL EVIDENCE")
print("=" * 80)

ranked_evidence = EvidenceRanker.rank(
    evidence_database
)

# ==========================================================
# SUSPECT RANKING
# ==========================================================

ranked_suspects = SuspectRanker.rank(
    suspect_database
)

# ==========================================================
# DISPLAY EVIDENCE
# ==========================================================

print("\n")
print("=" * 80)
print("FINAL EVIDENCE RESULTS")
print("=" * 80)

for evidence in ranked_evidence:

    print(f"Rank                     : {evidence.rank}")

    print(f"Evidence ID              : {evidence.metadata.evidence_id}")

    print(f"File Name                : {evidence.metadata.file_name}")

    print(f"Evidence Type            : {evidence.metadata.evidence_type}")

    print(f"File Size                : {evidence.metadata.size} Bytes")

    print(f"Generated Hash           : {evidence.generated_hash}")

    print(f"Hash Verified            : {evidence.hash_verified}")

    print(f"Duplicate                : {evidence.is_duplicate}")

    print(f"Authenticity Risk        : {evidence.authenticity_risk:.4f}")

    print(f"Context Intelligence     : {evidence.context_intelligence:.4f}")

    print(f"Behaviour Intelligence   : {evidence.behaviour_intelligence:.4f}")

    print(f"Semantic Intelligence    : {evidence.semantic_intelligence:.4f}")

    print(f"Investigation Intelligence : {evidence.investigative_intelligence:.4f}")

    print(f"IPI                      : {evidence.investigation_priority_index:.4f}")

    print(f"EPRA Score               : {evidence.epra_score:.2f}")

    print(f"Priority                 : {evidence.priority}")

    print("-" * 80)


# ==========================================================
# DISPLAY SUSPECTS
# ==========================================================

print("\n")
print("=" * 80)
print("SUSPECT RANKING")
print("=" * 80)

if len(ranked_suspects) == 0:

    print("No suspects detected.")

else:

    for suspect in ranked_suspects:

        print(f"Rank                 : {suspect.rank}")

        print(f"Suspect ID           : {suspect.suspect_id}")

        print(f"Suspect Name         : {suspect.suspect_name}")

        print(f"Linked Evidence      : {len(suspect.evidence_list)}")

        print(f"Total EPRA Score     : {suspect.total_epra_score:.2f}")

        print("-" * 80)


# ==========================================================
# SUMMARY
# ==========================================================

print("\n")
print("=" * 80)
print("INVESTIGATION SUMMARY")
print("=" * 80)

print(f"Total Evidence Processed : {len(ranked_evidence)}")

print(f"Total Suspects           : {len(ranked_suspects)}")

critical = len(
    [
        e for e in ranked_evidence
        if e.priority == "CRITICAL"
    ]
)

high = len(
    [
        e for e in ranked_evidence
        if e.priority == "HIGH"
    ]
)

medium = len(
    [
        e for e in ranked_evidence
        if e.priority == "MEDIUM"
    ]
)

low = len(
    [
        e for e in ranked_evidence
        if e.priority == "LOW"
    ]
)

very_low = len(
    [
        e for e in ranked_evidence
        if e.priority == "VERY LOW"
    ]
)

print(f"Critical Evidence        : {critical}")

print(f"High Priority            : {high}")

print(f"Medium Priority          : {medium}")

print(f"Low Priority             : {low}")

print(f"Very Low Priority        : {very_low}")

print("\n")

print("=" * 80)
print("EPRA V2 EXECUTION COMPLETED SUCCESSFULLY")
print("=" * 80)
