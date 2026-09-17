from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List, Dict, Any


# ==========================================
# 1. Reports Overview Counts Schema
# ==========================================

class ReportOverviewResponse(BaseModel):
    """Aggregated report counts strictly scoped to the authenticated user's assigned cases."""
    total_reports: int
    ongoing_reports: int
    completed_final_reports: int
    draft_reports: int
    not_generated_reports: int


# ==========================================
# 2. Reports Trend Line Chart Schema
# ==========================================

class ReportTrendItem(BaseModel):
    """Monthly report metrics for the trend line chart."""
    month: str
    year: int
    reports_generated: int
    final_reports: int


# ==========================================
# 3. Reports Table Schemas
# ==========================================

class ReportTableItem(BaseModel):
    """Individual row item for the Investigator Reports table."""
    case_id: str
    case_name: str
    crime_type: str
    case_status: str
    report_status: str  # NOT_GENERATED, DRAFT, GENERATED, FINAL
    investigation_progress: int  # 0 to 100 percentage
    last_updated: Optional[datetime] = None
    last_updated_display: Optional[str] = None
    report_id: Optional[str] = None
    download_url: Optional[str] = None
    view_url: Optional[str] = None
    can_view: bool = False
    can_download: bool = False

    class Config:
        from_attributes = True


class ReportTablePage(BaseModel):
    """Paginated response for the Investigator Reports table."""
    total_count: int
    total_pages: int
    page: int
    page_size: int
    items: List[ReportTableItem]


# ==========================================
# 4. View Report Structured Schema
# ==========================================

class ReportStructuredViewResponse(BaseModel):
    """Comprehensive structured report details covering all 12+ forensic sections."""
    report_id: Optional[str] = None
    case_id: str
    case_title: str
    crime_type: str
    case_status: str
    priority: str
    report_status: str  # NOT_GENERATED, DRAFT, GENERATED, FINAL
    is_draft: bool = False
    generated_at: Optional[datetime] = None
    generated_at_display: Optional[str] = None
    investigator_name: str
    investigator_id: Optional[str] = None
    assigned_cyber_expert: Optional[str] = None
    
    # Forensic Subsections
    report_info: Dict[str, Any] = {}
    case_information: Dict[str, Any] = {}
    investigator_information: Dict[str, Any] = {}
    cyber_expert_information: Dict[str, Any] = {}
    evidence_summary: Dict[str, Any] = {}
    evidence_metadata: List[Dict[str, Any]] = []
    integrity_verification: Dict[str, Any] = {}
    chain_of_custody: Dict[str, Any] = {}
    epra_analysis: Dict[str, Any] = {}
    cbir_analysis: Dict[str, Any] = {}
    suspect_ranking: Dict[str, Any] = {}
    relationship_analysis: Dict[str, Any] = {}
    timeline_reconstruction: Dict[str, Any] = {}
    investigation_findings: Dict[str, Any] = {}
    conclusion: Dict[str, Any] = {}

    download_url: Optional[str] = None
    preview_url: Optional[str] = None
    file_name: Optional[str] = None
    can_download: bool = False


# ==========================================
# 5. Backward Compatibility Schemas
# ==========================================

class ReportListResponse(BaseModel):
    case_id: str
    title: str
    investigator_name: str
    priority: str
    status: str
    created_at: datetime

    class Config:
        from_attributes = True


class TimelineEvent(BaseModel):
    event: str
    performed_by_role: str
    created_at: datetime

    class Config:
        from_attributes = True


class ReportDetailResponse(BaseModel):
    case_id: str
    title: str
    description: Optional[str]

    investigator_name: str

    priority: str
    status: str

    created_at: datetime
    updated_at: datetime

    timeline: List[TimelineEvent] = []

    epra_score: Optional[float] = None
    cbir_match: Optional[float] = None
    evidence_count: Optional[int] = None
    chain_of_custody: Optional[str] = None

    report_generated: bool = False

    class Config:
        from_attributes = True