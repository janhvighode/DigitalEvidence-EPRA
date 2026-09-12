from datetime import datetime
from typing import Any, Dict, List, Optional
from pydantic import BaseModel, Field


class RankedEvidenceResponse(BaseModel):
    rank: int
    evidence_id: str
    file_name: str
    evidence_type: str
    file_size: Optional[int] = None

    authenticity_risk: Optional[float] = None
    context_intelligence: Optional[float] = None
    behaviour_intelligence: Optional[float] = None
    semantic_intelligence: Optional[float] = None  # None / null when PENDING
    investigative_intelligence: Optional[float] = None

    ipi: Optional[float] = None
    epra_score: Optional[float] = None
    priority: Optional[str] = None

    semantic_status: str  # "MEASURED" or "PENDING"
    analysis_status: str  # "COMPLETE" or "PARTIAL / PENDING INPUTS"

    hash_verified: bool = False
    duplicate: bool = False

    pending_external_inputs: List[str] = Field(default_factory=list)
    processed_at: Optional[datetime] = None


class EvidenceEPRADetailResponse(BaseModel):
    evidence_id: str
    file_name: str
    evidence_type: str
    file_size: Optional[int] = None
    file_path: Optional[str] = None
    hash_verified: bool = False
    duplicate: bool = False
    original_evidence_id: Optional[str] = None

    authenticity_risk: Optional[float] = None
    context_intelligence: Optional[float] = None
    behaviour_intelligence: Optional[float] = None
    semantic_intelligence: Optional[float] = None
    investigative_intelligence: Optional[float] = None

    ipi: Optional[float] = None
    epra_score: Optional[float] = None
    priority: Optional[str] = None
    rank: Optional[int] = None

    semantic_status: str
    analysis_status: str
    pending_external_inputs: List[str] = Field(default_factory=list)

    hash_details: Optional[Dict[str, Any]] = None
    weights: Optional[Dict[str, float]] = None
    factors: Optional[Dict[str, Any]] = None
    processed_at: Optional[datetime] = None


class EPRASummaryResponse(BaseModel):
    case_id: str
    total_evidence: int
    critical: int
    high: int
    medium: int
    low: int
    very_low: int
    pending_analysis: int

    score_distribution: Optional[Dict[str, int]] = None
    average_epra_score: Optional[float] = None
    top_evidence: Optional[List[RankedEvidenceResponse]] = None
    last_processed_at: Optional[datetime] = None


class EPRARunRequest(BaseModel):
    demo_mode: Optional[bool] = False
    external_inputs: Optional[Dict[str, Dict[str, Any]]] = None


class EPRARunResponse(BaseModel):
    message: str
    case_id: str
    total_processed: int
    summary: EPRASummaryResponse
    ranked_evidence: List[RankedEvidenceResponse]
