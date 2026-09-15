"""
report_builder.py

Builds a structured investigation report from EPRA processing results.
Exposes complete intelligence dimensions, ADM weights, suspect correlations,
and clearly distinguishes genuine 0.0 scores from pending/unavailable external inputs.
"""

from datetime import datetime


class ReportBuilder:
    """
    Builds investigation report data.
    """

    @staticmethod
    def build(evidence_database, suspect_database):
        report = {
            # ----------------------------------
            # Report Information
            # ----------------------------------
            "report_title": "EPRA DIGITAL FORENSIC INVESTIGATION REPORT",
            "generated_at": datetime.now().strftime("%d-%m-%Y %H:%M:%S"),

            # ----------------------------------
            # Investigation Summary
            # ----------------------------------
            "summary": {
                "total_evidence": len(evidence_database),
                "total_suspects": len(suspect_database),
                "critical": sum(1 for e in evidence_database if e.priority == "CRITICAL"),
                "high": sum(1 for e in evidence_database if e.priority == "HIGH"),
                "medium": sum(1 for e in evidence_database if e.priority == "MEDIUM"),
                "low": sum(1 for e in evidence_database if e.priority == "LOW"),
                "very_low": sum(1 for e in evidence_database if e.priority == "VERY LOW"),
                "evidence_with_pending_inputs": sum(
                    1 for e in evidence_database
                    if getattr(e, "pending_external_inputs", {})
                )
            },

            # ----------------------------------
            # Evidence
            # ----------------------------------
            "evidence": [],

            # ----------------------------------
            # Suspects
            # ----------------------------------
            "suspects": []
        }

        # ======================================
        # Evidence Section
        # ======================================
        for evidence in evidence_database:
            pending_inputs = getattr(evidence, "pending_external_inputs", {}) or {}

            # Distinguish actual score 0.0 from pending/unavailable external input
            bi_status = "PENDING" if "BI" in pending_inputs else "MEASURED"
            si_status = "PENDING" if "SI" in pending_inputs else "MEASURED"

            report["evidence"].append({
                "rank": evidence.rank,
                "case_id": getattr(evidence.metadata, "case_id", ""),
                "evidence_id": getattr(evidence.metadata, "evidence_id", ""),
                "file_name": evidence.metadata.file_name,
                "evidence_type": evidence.metadata.evidence_type,
                "sha256": evidence.generated_hash,
                "hash_verified": getattr(evidence, "hash_verified", False),
                "chain_risk": getattr(evidence, "chain_risk", 0.0),
                "epra_score": evidence.epra_score,
                "priority": evidence.priority,
                "ipi": evidence.investigation_priority_index,
                "authenticity_risk": evidence.authenticity_risk,
                "context_intelligence": evidence.context_intelligence,
                "behaviour_intelligence": evidence.behaviour_intelligence,
                "behaviour_status": bi_status,
                "semantic_intelligence": evidence.semantic_intelligence,
                "semantic_status": si_status,
                "investigative_intelligence": evidence.investigative_intelligence,
                "adm_weights": {
                    "W_AR": evidence.authenticity_weight,
                    "W_CI": evidence.context_weight,
                    "W_BI": evidence.behaviour_weight,
                    "W_SI": evidence.semantic_weight,
                    "W_II": evidence.investigative_weight
                },
                "related_entities": getattr(evidence, "related_entities", []),
                "pending_external_inputs": pending_inputs
            })

        # ======================================
        # Suspect Section
        # ======================================
        for suspect in suspect_database:
            report["suspects"].append({
                "rank": suspect.rank,
                "suspect_id": suspect.suspect_id,
                "suspect_name": suspect.suspect_name,
                "linked_evidence": len(suspect.evidence_list),
                "linked_evidence_ids": getattr(suspect, "linked_evidence_ids", []),
                "total_epra_score": suspect.total_epra_score,
                "confidence_score": getattr(suspect, "confidence_score", 0.0)
            })

        return report