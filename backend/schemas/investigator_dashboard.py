from typing import Optional, List, Dict
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
