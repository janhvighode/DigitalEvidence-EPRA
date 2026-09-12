"""
behaviour_analyzer.py

Calculates Behaviour Intelligence (BI) for EPRA V2.

LOCKED FORMULA:
BI = (AF + RF + DF + PF) / 4

AF -> Access Frequency factor
RF -> Repetition Factor
DF -> Deletion Factor
PF -> Privilege Factor

Team Ownership Contract:
- Member 2 owns the backend/database and the actual behavioural/activity data.
- Production BI does NOT invent heuristics from filename keywords or type defaults.
- Legitimate derivation from actual backend fields is supported where data exists:
  - AF derived from access_count (normalized against threshold)
  - DF derived from access_action ("DELETE", "WIPE" -> 1.0, "MODIFY" -> 0.5, "OPEN" -> 0.0)
  - PF derived from owner / last_accessed_by ("root", "Administrator", "SYSTEM" -> 1.0)
  - RF derived from access_timeline if provided by audit logs.
- If behavioural inputs are unavailable in production, the dimension is marked as:
  MISSING EXTERNAL INPUT / INTEGRATION PENDING (Member 2 — Behavioural Backend)
- Heuristic fallback is isolated strictly to explicit demo/test mode.
"""

from typing import Optional
from ..utils.config import DEFAULT_DEMO_MODE


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
        Calculates Behaviour Intelligence using locked formula.
        All inputs must be normalized between 0 and 1.
        """
        score = (
            access_frequency +
            repetition_factor +
            deletion_factor +
            privilege_factor
        ) / 4

        return round(float(score), 4)

    @classmethod
    def derive_factors_from_metadata(cls, evidence):
        """
        DEMO/TEST ONLY:
        Heuristic factor derivation based on filename patterns and type defaults.
        This must NEVER be used in production.
        """
        metadata = getattr(evidence, "metadata", None)
        af = getattr(evidence, "access_frequency", 0.0)
        rf = getattr(evidence, "repetition_factor", 0.0)
        df = getattr(evidence, "deletion_factor", 0.0)
        pf = getattr(evidence, "privilege_factor", 0.0)

        if not metadata:
            return (
                af or 0.50,
                rf or 0.50,
                df or 0.10,
                pf or 0.50
            )

        # Access Frequency
        if af == 0.0:
            count = getattr(metadata, "access_count", 0)
            if count > 0:
                af = min(round(count / 20.0, 4), 1.0)
            else:
                etype = getattr(metadata, "evidence_type", "UNKNOWN")
                af_defaults = {
                    "LOG": 0.85,
                    "EXECUTABLE": 0.80,
                    "EMAIL": 0.75,
                    "DOCUMENT": 0.65,
                    "DATABASE": 0.75,
                    "SPREADSHEET": 0.60
                }
                af = af_defaults.get(etype, 0.40)

        # Repetition Factor
        if rf == 0.0:
            timeline = getattr(metadata, "access_timeline", [])
            if timeline:
                rf = min(round(len(timeline) / 5.0, 4), 1.0)
            else:
                rf = 0.50

        # Deletion Factor
        if df == 0.0:
            action = (getattr(metadata, "access_action", "") or "").upper()
            filename = (getattr(metadata, "file_name", "") or "").lower()
            etype = getattr(metadata, "evidence_type", "UNKNOWN")

            if "DELETE" in action or "recycle" in filename or "trash" in filename:
                df = 0.90
            elif "ransomware" in filename or (etype == "EXECUTABLE" and "malware" in filename):
                df = 0.85
            elif etype == "EMAIL" and "phishing" in filename:
                df = 0.40
            else:
                df = 0.05

        # Privilege Factor
        if pf == 0.0:
            owner = str(getattr(metadata, "owner", "") or "")
            source = str(getattr(metadata, "access_source", "") or "")
            if owner in ("0", "root", "Administrator", "SYSTEM") or "Event Log" in source:
                pf = 0.85
            elif getattr(metadata, "evidence_type", "") == "EXECUTABLE":
                pf = 0.80
            else:
                pf = 0.40

        return af, rf, df, pf

    @classmethod
    def derive_from_backend_facts(cls, evidence):
        """
        Production derivation from legitimate backend/metadata fields.
        Does NOT invent heuristic keywords or file type assumptions.
        """
        metadata = getattr(evidence, "metadata", None)
        if not metadata:
            return None

        has_data = False

        # 1. AF: from access_count if recorded
        af = getattr(evidence, "access_frequency", 0.0)
        count = getattr(metadata, "access_count", 0)
        if count > 0 and af == 0.0:
            af = min(round(count / 20.0, 4), 1.0)
            has_data = True

        # 2. RF: from access_timeline if recorded
        rf = getattr(evidence, "repetition_factor", 0.0)
        timeline = getattr(metadata, "access_timeline", [])
        if timeline and rf == 0.0:
            rf = min(round(len(timeline) / 5.0, 4), 1.0)
            has_data = True

        # 3. DF: from recorded access_action (audit event)
        df = getattr(evidence, "deletion_factor", 0.0)
        action = (getattr(metadata, "access_action", "") or "").upper()
        if action and df == 0.0:
            if "DELETE" in action or "WIPE" in action or "PURGE" in action:
                df = 1.0
                has_data = True
            elif "MODIFY" in action:
                df = 0.5
                has_data = True
            elif "OPEN" in action or "READ" in action or "COPY" in action:
                df = 0.0
                has_data = True

        # 4. PF: from recorded owner or last_accessed_by
        pf = getattr(evidence, "privilege_factor", 0.0)
        owner = str(getattr(metadata, "owner", "") or getattr(metadata, "last_accessed_by", "") or "")
        if owner and pf == 0.0:
            if owner in ("0", "root", "Administrator", "SYSTEM"):
                pf = 1.0
                has_data = True
            else:
                pf = 0.3
                has_data = True

        if not has_data and af == 0.0 and rf == 0.0 and df == 0.0 and pf == 0.0:
            return None

        return af, rf, df, pf

    @classmethod
    def process(cls, evidence, demo_mode: Optional[bool] = None):
        """
        Updates Behaviour Intelligence on Evidence object using locked formula.
        """
        if demo_mode is None:
            demo_mode = DEFAULT_DEMO_MODE

        # Case 1: Pre-supplied factors on evidence
        has_direct_factors = any([
            evidence.access_frequency > 0.0,
            evidence.repetition_factor > 0.0,
            evidence.deletion_factor > 0.0,
            evidence.privilege_factor > 0.0
        ])

        if has_direct_factors:
            af = min(max(evidence.access_frequency, 0.0), 1.0)
            rf = min(max(evidence.repetition_factor, 0.0), 1.0)
            df = min(max(evidence.deletion_factor, 0.0), 1.0)
            pf = min(max(evidence.privilege_factor, 0.0), 1.0)
            evidence.behaviour_intelligence = cls.calculate_behaviour_intelligence(af, rf, df, pf)
            return evidence

        # Case 2: Derive legitimately from actual backend audit fields
        backend_factors = cls.derive_from_backend_facts(evidence)
        if backend_factors is not None:
            af, rf, df, pf = backend_factors
            evidence.access_frequency = af
            evidence.repetition_factor = rf
            evidence.deletion_factor = df
            evidence.privilege_factor = pf
            evidence.behaviour_intelligence = cls.calculate_behaviour_intelligence(af, rf, df, pf)
            return evidence

        # Case 3: Demo mode fallback for offline testing
        if demo_mode:
            af, rf, df, pf = cls.derive_factors_from_metadata(evidence)
            evidence.access_frequency = af
            evidence.repetition_factor = rf
            evidence.deletion_factor = df
            evidence.privilege_factor = pf
            evidence.behaviour_intelligence = cls.calculate_behaviour_intelligence(af, rf, df, pf)
            return evidence

        # Case 4: Production mode with missing behavioural data
        evidence.behaviour_intelligence = 0.0
        if not hasattr(evidence, "pending_external_inputs"):
            evidence.pending_external_inputs = {}

        evidence.pending_external_inputs["BI"] = (
            "MISSING EXTERNAL INPUT / INTEGRATION PENDING (Member 2 — Behavioural Backend)"
        )

        return evidence