from typing import List, Optional, Dict, Any
from datetime import datetime
from pydantic import BaseModel, ConfigDict


class AdminAssignedUser(BaseModel):
    id: int
    name: str
    role: str

    model_config = ConfigDict(from_attributes=True)


class AdminLatestReportItem(BaseModel):
    report_id: str
    report_name: str
    report_type: str
    status: str  # DRAFT, GENERATED, FINAL
    is_draft: bool = False
    generated_at: Optional[datetime] = None
    generated_at_formatted: Optional[str] = None
    generated_by_id: Optional[str] = None
    generated_by_name: Optional[str] = None
    generated_by_role: Optional[str] = None
    file_available: bool = False
    file_format: str = "PDF"
    file_size_bytes: int = 0
    file_size_formatted: str = "0 B"
    view_url: Optional[str] = None
    download_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class CaseReportJourney(BaseModel):
    evidence_collected: bool = False
    analysis_completed: Optional[bool] = None  # None if no evidence, True if all analyzed, False if pending
    report_generated: bool = False
    finalized: bool = False

    model_config = ConfigDict(from_attributes=True)


class AdminCaseReportItem(BaseModel):
    case_id: str
    internal_case_id: int
    case_title: str
    case_priority: str
    case_status: str
    created_at: Optional[datetime] = None
    assigned_investigator: Optional[AdminAssignedUser] = None
    assigned_cyber_expert: Optional[AdminAssignedUser] = None
    report_status: str  # NOT_GENERATED, DRAFT, GENERATED, FINAL
    reports_count: int = 0
    latest_report: Optional[AdminLatestReportItem] = None
    journey: CaseReportJourney

    model_config = ConfigDict(from_attributes=True)


class AdminCaseReportPage(BaseModel):
    total_items: int
    total_pages: int
    page: int
    page_size: int
    items: List[AdminCaseReportItem]

    model_config = ConfigDict(from_attributes=True)


class AdminReportCoverageResponse(BaseModel):
    total_cases: int
    cases_with_reports: int
    cases_without_reports: int
    coverage_percentage: float
    status_counts: Dict[str, int]

    model_config = ConfigDict(from_attributes=True)


class AdminReportHistoryItem(BaseModel):
    report_id: str
    report_name: str
    report_type: str
    status: str  # DRAFT, GENERATED, FINAL
    is_draft: bool = False
    file_format: str = "PDF"
    file_size_bytes: int = 0
    file_size_formatted: str = "0 B"
    generated_at: Optional[datetime] = None
    generated_at_formatted: Optional[str] = None
    generated_by_id: Optional[str] = None
    generated_by_name: Optional[str] = None
    generated_by_role: Optional[str] = None
    file_available: bool = False
    view_url: Optional[str] = None
    download_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class AdminReportHistoryResponse(BaseModel):
    case_id: str
    internal_case_id: int
    total_reports: int
    reports: List[AdminReportHistoryItem]

    model_config = ConfigDict(from_attributes=True)
