from typing import List, Dict, Optional, Any
from datetime import datetime
from pydantic import BaseModel, ConfigDict, Field

from schemas.possible_entity import RankedEntityResponse


# ============================================================
# CASE NOTES SCHEMAS
# ============================================================

class CaseNoteCreate(BaseModel):
    content: str = Field(..., min_length=1, description="Note text content, non-blank")


class CaseNoteResponse(BaseModel):
    id: int
    case_id: int
    content: str
    created_by: int
    created_by_name: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


# ============================================================
# BASIC INFORMATION SCHEMAS
# ============================================================

class CaseBasicInformation(BaseModel):
    id: int
    case_id: str
    case_name: str
    crime_type: str
    priority: str
    status: str
    assigned_date: Optional[datetime] = None
    assigned_by: Optional[str] = None
    description: Optional[str] = None
    investigator_id: Optional[int] = None
    investigator_name: Optional[str] = None
    cyber_expert_id: Optional[int] = None
    cyber_expert_name: Optional[str] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


# ============================================================
# EVIDENCE SUMMARY SCHEMAS
# ============================================================

class EvidenceSummaryCategories(BaseModel):
    images: int = 0
    documents: int = 0
    videos: int = 0
    audio: int = 0
    others: int = 0


class EvidenceSummaryResponse(BaseModel):
    total_evidence: int = 0
    counts_by_type: Dict[str, int] = {}
    summary_categories: EvidenceSummaryCategories = Field(default_factory=EvidenceSummaryCategories)


# ============================================================
# TIMELINE SCHEMAS
# ============================================================

class TimelineEventItem(BaseModel):
    event_id: str
    case_id: str
    event_type: str
    title: str
    description: str
    timestamp: Optional[str] = None
    actor: Optional[str] = None
    actor_role: Optional[str] = None
    source: Optional[str] = None
    status: Optional[str] = "COMPLETED"


# ============================================================
# COMPREHENSIVE CASE DETAILS AGGREGATOR SCHEMA
# ============================================================

class CaseDetailsResponse(BaseModel):
    basic_information: CaseBasicInformation
    involved_entities: List[RankedEntityResponse] = []
    timeline: List[TimelineEventItem] = []
    evidence_summary: EvidenceSummaryResponse
    case_notes: List[CaseNoteResponse] = []
