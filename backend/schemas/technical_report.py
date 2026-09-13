from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field
from enum import Enum


class ReportType(str, Enum):
    COMPREHENSIVE = "Comprehensive Forensic Report"
    EVIDENCE_SUMMARY = "Evidence Summary Report"
    CHAIN_OF_CUSTODY = "Chain of Custody Report"
    HASH_VERIFICATION = "Hash Verification Report"
    TIMELINE = "Timeline Report"
    HASH_MANIFEST = "JSON Hash Manifest"


ALL_REPORT_SECTIONS = [
    "case_info",
    "evidence_details",
    "metadata_summary",
    "hash_verification",
    "chain_of_custody",
    "timeline",
    "suspect_summary",
    "epra_analysis",
    "activity_logs",
    "conclusions"
]

DEFAULT_SECTIONS_BY_TYPE = {
    ReportType.COMPREHENSIVE: ALL_REPORT_SECTIONS,
    ReportType.EVIDENCE_SUMMARY: ["case_info", "metadata_summary", "evidence_details", "conclusions"],
    ReportType.CHAIN_OF_CUSTODY: ["case_info", "chain_of_custody", "timeline", "activity_logs"],
    ReportType.HASH_VERIFICATION: ["case_info", "hash_verification", "metadata_summary"],
    ReportType.TIMELINE: ["case_info", "timeline", "activity_logs"],
    ReportType.HASH_MANIFEST: ["case_info", "hash_verification", "evidence_details"]
}


class SuspectInput(BaseModel):
    suspect_id: Optional[str] = None
    name: str
    role_or_relation: Optional[str] = None
    externally_supplied_ranking: Optional[int] = None
    linked_evidence_ids: List[str] = Field(default_factory=list)
    notes: Optional[str] = None


class ReportRequest(BaseModel):
    case_id: Optional[str] = Field(default=None, json_schema_extra={"example": "CASE-2025-047"})
    case_title: Optional[str] = Field(default=None, json_schema_extra={"example": "Cyber Fraud Investigation"})
    crime_type: Optional[str] = Field(default=None, json_schema_extra={"example": "Financial Fraud"})
    report_type: ReportType = Field(default=ReportType.COMPREHENSIVE)
    
    investigator_name: Optional[str] = Field(default=None, json_schema_extra={"example": "Jane Doe"})
    investigator_id: Optional[str] = Field(default=None, json_schema_extra={"example": "INV-101"})
    investigator_role: Optional[str] = Field(default=None, json_schema_extra={"example": "Cyber Expert"})
    department: Optional[str] = Field(default=None, json_schema_extra={"example": "Cyber Cell, Mumbai"})
    
    selected_sections: Optional[List[str]] = Field(default=None)
    evidence_ids: Optional[List[str]] = Field(default=None)
    
    # Investigator supplied conclusions
    conclusions_text: Optional[str] = Field(default=None)
    recommendations_text: Optional[str] = Field(default=None)
    
    # Optional supplied records (preserves provenance without fabricating)
    suspect_records: Optional[List[SuspectInput]] = Field(default=None)
    events: Optional[List[str]] = Field(default=None)
    
    # Backward compatible toggles
    include_custody: bool = Field(default=True)
    include_activity: bool = Field(default=True)
    include_timeline: bool = Field(default=True)


class ReportSummaryResponse(BaseModel):
    case_id: str
    total_evidence: int
    verified_evidence: int
    tampered_evidence: int
    pending_evidence: int
    unknown_evidence: int = 0
    total_reports: Optional[int] = 0
    latest_report_name: Optional[str] = None
    latest_generated_at: Optional[str] = None


class ReportHistoryItem(BaseModel):
    report_id: str
    report_name: str
    case_id: str
    case_title: Optional[str] = None
    crime_type: Optional[str] = None
    report_type: str
    file_format: str
    file_size_bytes: int
    file_size_formatted: str
    generated_at: Optional[str] = None
    generated_at_formatted: Optional[str] = None
    generated_by: str
    generated_by_role: Optional[str] = None
    download_url: str
    preview_url: str


class ReportHistoryResponse(BaseModel):
    case_id: str
    total_reports: int
    page: int
    page_size: int
    total_pages: int
    reports: List[ReportHistoryItem]


class ReportGenerateResponse(BaseModel):
    status: str = "success"
    is_draft: bool = False
    message: str
    report_id: str
    case_id: str
    report_type: str
    file_format: str
    file_name: str
    pdf_path: Optional[str] = None
    download_url: Optional[str] = None
    preview_url: Optional[str] = None
    evidence_summary: Dict[str, Any]
    total_evidence_files: int
    selected_sections: List[str]
    crime_type: Optional[str] = None
    department: Optional[str] = None
    file_size_bytes: int = 0
    file_size_formatted: str = "0 B"
