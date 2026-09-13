from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field


# ==========================================
# 1. SUMMARY STATS (7 CARDS)
# ==========================================

class InvestigatorDashboardStats(BaseModel):
    total_assigned_cases: int = Field(..., description="Total cases assigned to current investigator")
    active_cases: int = Field(..., description="Active cases: Open + In Progress + Under Review")
    evidence_uploaded: int = Field(..., description="All evidence items belonging to investigator's assigned cases")
    evidence_pending_analysis: int = Field(..., description="Evidence items pending EPRA analysis")
    new_analysis_results: int = Field(..., description="Completed analysis results or unread notifications")
    cases_requiring_attention: int = Field(..., description="Cases with tampered evidence, critical EPRA, or urgent status")
    completed_cases: int = Field(..., description="Closed cases")


# ==========================================
# 2. CASES REQUIRING ATTENTION
# ==========================================

class CaseRequiringAttentionItem(BaseModel):
    id: int
    case_id: str
    title: str
    priority: str
    status: str
    reason: str
    updated_at: Optional[datetime] = None


# ==========================================
# 3. EVIDENCE STATUS BREAKDOWN
# ==========================================

class InvestigatorEvidenceStatusResponse(BaseModel):
    total_evidence: int
    # Analysis dimensions
    analyzed: int
    pending_analysis: int
    # Integrity dimensions
    integrity_verified: int
    integrity_issue: int
    pending_verification: int
    # Formatted breakdowns for frontend charts
    analysis_breakdown: Dict[str, int]
    integrity_breakdown: Dict[str, int]


# ==========================================
# 4. CASE STATUS DISTRIBUTION
# ==========================================

class CaseStatusDistributionResponse(BaseModel):
    open: int
    in_progress: int
    under_review: int
    closed: int
    total: int


# ==========================================
# 5. MY ASSIGNED CASES
# ==========================================

class InvestigatorCaseItem(BaseModel):
    id: int
    case_id: str
    title: str
    description: Optional[str] = None
    priority: str
    status: str
    assigned_cyber_expert: Optional[str] = None
    evidence_count: int
    analyzed_evidence_count: int
    pending_analysis_count: int
    analysis_progress: float
    created_at: datetime
    updated_at: Optional[datetime] = None


class InvestigatorMyCasesPage(BaseModel):
    total: int
    page: int
    limit: int
    cases: List[InvestigatorCaseItem]


# ==========================================
# 6. CASE OVERVIEW TAB SCHEMAS
# ==========================================

class TeamMemberItem(BaseModel):
    id: int
    name: str
    email: str
    role: str


class CaseDetailItem(BaseModel):
    id: int
    case_id: str
    title: str
    description: Optional[str] = None
    priority: str
    status: str
    created_at: datetime
    updated_at: Optional[datetime] = None


class CaseStatisticsItem(BaseModel):
    total_evidence: int
    analyzed_evidence: int
    pending_analysis: int
    high_priority_evidence: int
    investigation_progress: float


class TimelineActivityItem(BaseModel):
    id: Any
    event: str
    actor_name: Optional[str] = None
    role: Optional[str] = None
    timestamp: datetime


class CaseOverviewResponse(BaseModel):
    case: CaseDetailItem
    assigned_investigator: TeamMemberItem
    assigned_cyber_expert: Optional[TeamMemberItem] = None
    statistics: CaseStatisticsItem
    recent_activity: List[TimelineActivityItem]


# ==========================================
# 7. EVIDENCE MANAGEMENT TAB SCHEMAS
# ==========================================

class CaseEvidenceSummaryResponse(BaseModel):
    total_evidence: int
    analyzed: int
    pending_analysis: int
    integrity_issues: int


class InvestigatorEvidenceRepositoryItem(BaseModel):
    id: int
    evidence_id: str
    file_name: str
    file_type: str
    file_size: int
    uploaded_on: datetime
    current_hash: Optional[str] = None
    integrity_status: str
    analysis_status: str
    priority: Optional[str] = None
    epra_score: Optional[float] = None
    rank: Optional[int] = None


class InvestigatorEvidenceRepositoryPage(BaseModel):
    total: int
    page: int
    limit: int
    items: List[InvestigatorEvidenceRepositoryItem]


class InvestigatorEvidenceDetailResponse(BaseModel):
    id: int
    evidence_id: str
    file_name: str
    file_type: str
    file_size: int
    uploaded_on: datetime
    uploaded_by: Optional[str] = None
    current_hash: Optional[str] = None
    original_hash: Optional[str] = None
    hash_match: Optional[bool] = None
    tampered: Optional[bool] = None
    integrity_status: str
    verification_date: Optional[datetime] = None
    verified_by: Optional[str] = None
    analysis_status: str
    priority: Optional[str] = None
    epra_score: Optional[float] = None
    rank: Optional[int] = None
    ipi: Optional[float] = None
    risk_factors: Optional[Dict[str, Optional[float]]] = None
    pending_external_inputs: Optional[List[str]] = None
    metadata: Optional[Dict[str, Any]] = None


# ==========================================
# 8. ANALYSIS PROGRESS TAB SCHEMAS
# ==========================================

class AnalysisProgressSummaryResponse(BaseModel):
    case_id: str
    total_evidence: int
    analyzed_evidence: int
    pending_analysis: int
    partial_analysis: int
    high_critical_evidence: int
    overall_analysis_progress: float


class EvidenceAnalysisItem(BaseModel):
    id: int
    evidence_id: str
    file_name: str
    file_type: str
    analysis_status: str
    priority: Optional[str] = None
    epra_score: Optional[float] = None
    rank: Optional[int] = None
    pending_inputs: List[str] = Field(default_factory=list)
    processed_at: Optional[datetime] = None


class EvidenceAnalysisPage(BaseModel):
    total: int
    page: int
    limit: int
    items: List[EvidenceAnalysisItem]


class EPRAPriorityDistributionResponse(BaseModel):
    case_id: str
    critical: int
    high: int
    medium: int
    low: int
    very_low: int
    total_analyzed: int


class PendingAnalysisItem(BaseModel):
    id: int
    evidence_id: str
    file_name: str
    file_type: str
    analysis_status: str
    pending_inputs: List[str] = Field(default_factory=list)
    last_updated: Optional[datetime] = None


class PendingAnalysisResponse(BaseModel):
    case_id: str
    total_pending: int
    items: List[PendingAnalysisItem]


class InvestigatorAnalysisDetailResponse(BaseModel):
    evidence_id: str
    file_name: str
    evidence_type: str
    file_size: Optional[int] = None
    analysis_status: str
    semantic_status: Optional[str] = None
    authenticity_risk: Optional[float] = None
    context_intelligence: Optional[float] = None
    behaviour_intelligence: Optional[float] = None
    semantic_intelligence: Optional[float] = None
    investigative_intelligence: Optional[float] = None
    ipi: Optional[float] = None
    epra_score: Optional[float] = None
    priority: Optional[str] = None
    rank: Optional[int] = None
    pending_inputs: List[str] = Field(default_factory=list)
    hash_verified: bool = False
    duplicate: bool = False
    processed_at: Optional[datetime] = None


# ==========================================
# 9. RELATIONSHIP VIEW TAB SCHEMAS
# ==========================================

class RelationshipNodeDetailResponse(BaseModel):
    node_id: str
    node_type: str
    label: str
    properties: Dict[str, Any]
    connected_nodes_count: int
    connected_edges: List[Dict[str, Any]]


# ==========================================
# 10. CASE ACTIVITY TAB SCHEMAS
# ==========================================

class InvestigatorCaseActivitySummaryResponse(BaseModel):
    case_id: str
    total_activity_count: int
    evidence_activity_count: int
    analysis_activity_count: int
    integrity_activity_count: int
    custody_activity_count: int
    relationship_activity_count: int
    report_activity_count: int
    case_activity_count: int
    latest_activity_at: Optional[datetime] = None
    latest_activity_formatted: Optional[str] = None


class InvestigatorCaseActivityItem(BaseModel):
    activity_id: str
    case_id: str
    activity_type: str  # CASE, EVIDENCE, METADATA, INTEGRITY, CUSTODY, EPRA, CBIR, RELATIONSHIP, REPORT
    action: str
    title: str
    description: str
    source_module: str
    evidence_id: Optional[str] = None
    report_id: Optional[str] = None
    actor_user_id: Optional[int] = None
    actor_name: Optional[str] = None
    actor_role: Optional[str] = None
    timestamp: datetime
    timestamp_formatted: Optional[str] = None
    status: Optional[str] = None
    additional_details: Optional[Dict[str, Any]] = None


class InvestigatorCaseActivityPage(BaseModel):
    case_id: str
    total: int
    page: int
    limit: int
    total_pages: int
    activities: List[InvestigatorCaseActivityItem]


class InvestigatorActivityDetailResponse(BaseModel):
    activity_id: str
    case_id: str
    activity_type: str
    action: str
    title: str
    description: str
    source_module: str
    timestamp: datetime
    timestamp_formatted: Optional[str] = None
    actor_name: Optional[str] = None
    actor_role: Optional[str] = None
    evidence_id: Optional[str] = None
    report_id: Optional[str] = None
    status: Optional[str] = None
    evidence_details: Optional[Dict[str, Any]] = None
    integrity_details: Optional[Dict[str, Any]] = None
    metadata_details: Optional[Dict[str, Any]] = None
    epra_details: Optional[Dict[str, Any]] = None
    custody_details: Optional[Dict[str, Any]] = None
    report_details: Optional[Dict[str, Any]] = None
    relationship_details: Optional[Dict[str, Any]] = None
    raw_details: Optional[Dict[str, Any]] = None



