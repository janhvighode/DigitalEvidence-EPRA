"""
config.py

Runtime configuration for EPRA V2 engine.
Author : Janhvi Ghode
Project: Smart Digital Evidence Prioritization System using EPRA
"""

# Runtime demo mode flag:
# When False (Production), missing external inputs (Member 2 BI, Member 3 SI, Member 5 facts)
# are NOT fabricated and are recorded as pending external integrations.
# When True (Demo/Test), isolated heuristics and fixtures execute for standalone demonstration.
DEFAULT_DEMO_MODE: bool = False
