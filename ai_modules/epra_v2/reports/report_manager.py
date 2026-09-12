"""
report_manager.py

Generates all investigation reports.
"""

from .report_builder import ReportBuilder
from .json_exporter import JSONExporter
from .csv_exporter import CSVExporter
from .pdf_generator import PDFGenerator


class ReportManager:

    @classmethod
    def generate_all_reports(
        cls,
        evidence_database,
        suspect_database
    ):

        report = ReportBuilder.build(
            evidence_database,
            suspect_database
        )

        json_file = JSONExporter.export(
            report
        )

        csv_file = CSVExporter.export(
            report
        )

        pdf_file = PDFGenerator.export(
            report
        )

        return {

            "json": json_file,

            "csv": csv_file,

            "pdf": pdf_file

        }