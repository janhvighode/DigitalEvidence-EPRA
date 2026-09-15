from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List, Dict, Any


# ==============================================================================
# 1. EVIDENCE COUNTS SCHEMA
# ==============================================================================

class EvidenceCountsItem(BaseModel):
    total_evidence_collected: int
    evidence_analyzed: int
    pending_analysis: int
    integrity_issues: int
    evidence_added_today: int
    last_evidence_added_at: Optional[datetime] = None


# ==============================================================================
# 2. NEXT-STAGE READINESS SCHEMA
# ==============================================================================

class NextStageReadinessItem(BaseModel):
    ready_for_next_stage: bool
    next_recommended_stage: Optional[str] = None
    blocking_issues: List[str] = []


# ==============================================================================
# 3. CASE STATUS SUMMARY ITEM (BOARD / LIST ITEM)
# ==============================================================================

class CaseStatusSummaryItem(BaseModel):
    id: int
    case_id: str
    case_title: str
    crime_type: str
    priority: str
    current_status: str  # OPEN, IN_PROGRESS, UNDER_REVIEW, CLOSED (canonical)
    raw_status: str      # Original DB representation (e.g., "In Progress")

    assigned_investigator: str
    assigned_cyber_expert: Optional[str] = None

    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    days_since_opened: int
    investigation_deadline: Optional[str] = None

    investigation_progress: int  # 0 - 100 percentage

    # Evidence details
    total_evidence_collected: int
    evidence_analyzed: int
    pending_analysis: int
    integrity_issues: int
    evidence_added_today: int
    last_evidence_added_at: Optional[datetime] = None
    evidence_counts: Optional[EvidenceCountsItem] = None

    # Report & Activity
    report_status: str  # NOT_GENERATED, DRAFT, GENERATED, FINAL
    last_activity: Optional[str] = None
    last_activity_at: Optional[datetime] = None

    # Health & Readiness
    case_health: str    # ON_TRACK, NEEDS_ATTENTION, BLOCKED
    module_readiness: Dict[str, str]
    next_stage_readiness: NextStageReadinessItem

    class Config:
        from_attributes = True


# ==============================================================================
# 4. CASE STATUS BOARD RESPONSE
# ==============================================================================

class CaseStatusBoardResponse(BaseModel):
    open_count: int
    in_progress_count: int
    under_review_count: int
    closed_count: int
    total_cases: int

    cases: List[CaseStatusSummaryItem]
    sections: Dict[str, List[CaseStatusSummaryItem]]

    page: int = 1
    page_size: int = 10
    total_pages: int = 1


# ==============================================================================
# 5. STATUS HISTORY ITEM
# ==============================================================================

class StatusHistoryItem(BaseModel):
    id: int
    case_id: str
    old_status: str
    new_status: str
    changed_by_user_id: int
    changed_by_name: Optional[str] = None
    changed_by_role: str
    changed_at: datetime
    remark: Optional[str] = None

    class Config:
        from_attributes = True


# ==============================================================================
# 6. CASE INFORMATION DETAIL
# ==============================================================================

class CaseInformationItem(BaseModel):
    id: int
    case_id: str
    title: str
    description: Optional[str] = None
    crime_type: str
    priority: str
    current_status: str
    raw_status: str
    assigned_investigator: str
    assigned_cyber_expert: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None
    days_since_opened: int
    investigation_deadline: Optional[str] = None


# ==============================================================================
# 7. CASE STATUS EXPANDED / DETAIL RESPONSE
# ==============================================================================

class CaseStatusDetailResponse(BaseModel):
    case_information: CaseInformationItem
    evidence_summary: EvidenceCountsItem
    investigation_progress: int
    module_readiness: Dict[str, str]
    case_health: str
    blocking_issues: List[str]
    next_recommended_stage: Optional[str] = None
    ready_for_next_stage: bool
    report_status: str
    status_history: List[StatusHistoryItem]


# ==============================================================================
# 8. UPDATE CASE STATUS REQUEST & RESPONSE
# ==============================================================================

class CaseStatusUpdateRequest(BaseModel):
    new_status: str
    remark: Optional[str] = None


class CaseStatusUpdateResponse(BaseModel):
    message: str
    case_id: str
    previous_status: str
    current_status: str
    changed_at: datetime
    remark: Optional[str] = None
