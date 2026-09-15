"""
csv_exporter.py

Exports Evidence Ranking and intelligence dimensions to CSV.
Clearly indicates whether dimensions are genuinely measured or integration pending.
"""

import csv
from pathlib import Path


class CSVExporter:

    @staticmethod
    def export(report_data, output_directory="generated_reports"):
        output_directory = Path(output_directory)
        output_directory.mkdir(exist_ok=True)

        output_file = output_directory / "Investigation_Report.csv"

        with open(
            output_file,
            "w",
            newline="",
            encoding="utf-8"
        ) as csvfile:
            writer = csv.writer(csvfile)

            writer.writerow([
                "Rank",
                "Evidence ID",
                "File Name",
                "Evidence Type",
                "SHA256",
                "EPRA Score",
                "Priority",
                "IPI",
                "Authenticity Risk",
                "Context Intelligence",
                "Behaviour Intelligence",
                "BI Status",
                "Semantic Intelligence",
                "SI Status",
                "Investigative Intelligence",
                "Pending Inputs"
            ])

            for evidence in report_data["evidence"]:
                pending_str = "; ".join(
                    f"{k}: {v}" for k, v in evidence.get("pending_external_inputs", {}).items()
                ) if evidence.get("pending_external_inputs") else "NONE"

                writer.writerow([
                    evidence["rank"],
                    evidence["evidence_id"],
                    evidence["file_name"],
                    evidence["evidence_type"],
                    evidence["sha256"],
                    evidence["epra_score"],
                    evidence["priority"],
                    evidence["ipi"],
                    evidence["authenticity_risk"],
                    evidence["context_intelligence"],
                    evidence["behaviour_intelligence"],
                    evidence.get("behaviour_status", "MEASURED"),
                    evidence["semantic_intelligence"],
                    evidence.get("semantic_status", "MEASURED"),
                    evidence["investigative_intelligence"],
                    pending_str
                ])

        return output_file