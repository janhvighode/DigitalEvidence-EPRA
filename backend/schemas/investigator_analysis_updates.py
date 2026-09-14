from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field


# ==============================================================================
# 1. SUMMARY STATS CONTRACT
# ==============================================================================

class AnalysisUpdatesSummaryResponse(BaseModel):
    total_cases: int = Field(..., description="Total cases assigned to the logged-in investigator")
    in_analysis: int = Field(..., description="Assigned cases where analysis has started but is not fully complete")
    attention_required: int = Field(..., description="Assigned cases with genuine alerts (tampered hashes, critical EPRA, etc.)")
    completed: int = Field(..., description="Assigned cases with 100% applicable analysis modules completed")
    pending: int = Field(..., description="Assigned cases with zero analysis activity yet")
    last_refreshed: Optional[datetime] = Field(None, description="Timestamp when summary was calculated")


# ==============================================================================
# 2. MODULE STATUS & CASE INTELLIGENCE CONTRACTS
# ==============================================================================

class AssignedCyberExpertInfo(BaseModel):
    id: Optional[int] = None
    name: Optional[str] = None
    email: Optional[str] = None


class ModuleStatusItem(BaseModel):
    status: str = Field(..., description="Normalized status: COMPLETED, IN_PROGRESS, PENDING, ATTENTION_REQUIRED, or N/A")
    is_completed: bool = Field(False, description="True if analysis execution has completed for this module")
    updated_at: Optional[datetime] = Field(None, description="Timestamp of most recent analysis update for this module")
    details: Optional[str] = Field(None, description="Brief context, e.g. '8 files analyzed', '1 item compromised'")


class AnalysisModulesStatus(BaseModel):
    integrity: ModuleStatusItem
    metadata: ModuleStatusItem
    epra: ModuleStatusItem
    cbir: ModuleStatusItem
    entity_ranking: ModuleStatusItem
    relationship: ModuleStatusItem
    technical_report: ModuleStatusItem


class CaseIntelligenceSummary(BaseModel):
    highest_epra_priority: Optional[str] = Field(None, description="Highest priority across case EPRA items: Critical, High, Medium, Low, Very Low")
    possible_entities: int = Field(0, description="Genuine count of possible suspect entities linked to this case")
    relationships_found: int = Field(0, description="Total relationship graph edges/links discovered within this case")
    integrity_status: str = Field("PENDING", description="Case-level integrity status: VERIFIED, ATTENTION_REQUIRED, PENDING")
    technical_report_status: str = Field("PENDING", description="Report status: COMPLETED, PENDING")
    total_evidence: int = Field(0, description="Total genuine evidence files registered for this case")


class CaseLatestUpdate(BaseModel):
    module: Optional[str] = Field(None, description="Module that recorded the most recent activity")
    message: Optional[str] = Field(None, description="Descriptive case-level update message")
    updated_at: Optional[datetime] = Field(None, description="Genuine timestamp of the latest event")


class CaseAnalysisOverviewItem(BaseModel):
    id: Optional[int] = Field(None, description="Database integer primary key")
    case_id: str = Field(..., description="Human-readable case ID, e.g. C-1024")
    title: str = Field(..., description="Case title")
    crime_type: Optional[str] = Field(None, description="Category of cyber crime")
    case_priority: str = Field(..., description="Case priority: Low, Medium, High, Critical")
    case_status: str = Field(..., description="Case status: Open, In Progress, Under Review, Closed")
    assigned_cyber_expert: Optional[AssignedCyberExpertInfo] = None
    analysis_progress: float = Field(..., ge=0.0, le=100.0, description="Genuine percentage of completed applicable modules (0-100%)")
    analysis_state: str = Field(..., description="Derived case analysis state: ATTENTION_REQUIRED, COMPLETED, IN_ANALYSIS, PENDING")
    analysis_modules: AnalysisModulesStatus
    case_intelligence: CaseIntelligenceSummary
    latest_update: Optional[CaseLatestUpdate] = None
    attention_required: bool = Field(False, description="True if genuine attention conditions are triggered")
    attention_reasons: List[str] = Field(default_factory=list, description="Specific factual reasons why attention is required")


class CaseAnalysisOverviewPage(BaseModel):
    total: int = Field(..., description="Total matching assigned cases")
    page: int = Field(..., ge=1)
    page_size: int = Field(..., ge=1)
    total_pages: int = Field(...)
    items: List[CaseAnalysisOverviewItem] = Field(default_factory=list)


# ==============================================================================
# 3. ANALYSIS PULSE (RECENT ACTIVITY) CONTRACTS
# ==============================================================================

class AnalysisPulseItem(BaseModel):
    case_id: str = Field(..., description="Case code, e.g. C-1024")
    case_title: str = Field(..., description="Title of the case")
    module: str = Field(..., description="Forensic module name")
    event_type: str = Field(..., description="Canonical event code")
    message: str = Field(..., description="Case-level description of forensic activity")
    status: str = Field(..., description="Status outcome of the activity")
    timestamp: datetime = Field(..., description="Genuine timestamp of activity occurrence")
    timestamp_formatted: Optional[str] = Field(None, description="Formatted display date and time")


class AnalysisPulsePage(BaseModel):
    total: int = Field(..., description="Total available activity events")
    page: int = Field(..., ge=1)
    limit: int = Field(..., ge=1)
    total_pages: int = Field(...)
    items: List[AnalysisPulseItem] = Field(default_factory=list)
