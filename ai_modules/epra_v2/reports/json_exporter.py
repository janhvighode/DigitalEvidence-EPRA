"""
json_exporter.py

Exports EPRA investigation report to JSON.
"""

import json
from pathlib import Path


class JSONExporter:

    @staticmethod
    def export(report_data, output_directory="generated_reports"):

        output_directory = Path(output_directory)
        output_directory.mkdir(exist_ok=True)

        output_file = output_directory / "Investigation_Report.json"

        with open(output_file, "w", encoding="utf-8") as file:

            json.dump(
                report_data,
                file,
                indent=4,
                default=str
            )

        return output_file