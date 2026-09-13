from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field


class CBIRImageEvidenceItem(BaseModel):
    """Image evidence available in the case for query selection."""
    id: int
    evidence_id: str
    file_name: str
    file_type: str
    file_size: int
    created_at: Optional[str] = None


class CBIRImagesListResponse(BaseModel):
    """List of available genuine image evidence for the selected case."""
    case_id: int
    total_images: int
    images: List[CBIRImageEvidenceItem]


class CBIRCompareRequest(BaseModel):
    """CBIR Comparison Request."""
    query_evidence_id: int = Field(..., description="Numeric primary key (id) of the query evidence in evidences table")
    classification: Optional[str] = Field(default=None, description="Optional classification filter (e.g. All, Exact Duplicate, Very Strong Visual Match, Strong Visual Match, Possible Visual Resemblance, Weak Visual Resemblance, No Significant Visual Match)")
    min_visual_similarity: Optional[float] = Field(default=0.0, ge=0.0, le=1.0, description="Minimum visual similarity threshold (0.0 to 1.0)")
    top_k: Optional[int] = Field(default=50, ge=1, le=100, description="Maximum number of candidate matches to return")


class CBIRCandidateResult(BaseModel):
    """Full candidate result item matching approved 18-column/field design."""
    case_id: int
    query_evidence_id: str
    query_filename: str
    candidate_evidence_id: str
    candidate_filename: str
    edge_similarity: float
    orb_similarity: float
    color_similarity: float
    grayscale_similarity: float
    visual_similarity_score: float
    semantic_score: float
    sha256_exact_duplicate: bool
    classification: str
    confidence: str
    verification_required: bool
    recommendation: str
    reason: str
    rank: int


class CBIRSearchSummary(BaseModel):
    """Actual runtime search statistics and counts."""
    total_same_case_images: int
    candidates_analyzed: int
    query_excluded_id: str
    result_count: int


class CBIRCompareResponse(BaseModel):
    """Response returned when CBIR comparison finishes."""
    case_id: int
    query_evidence_id: str
    query_filename: str
    summary: CBIRSearchSummary
    results: List[CBIRCandidateResult]
    forensic_disclaimer: str


class CBIRCandidateDetailResponse(BaseModel):
    """Detailed candidate comparison view for 'View Details' modal."""
    candidate: CBIRCandidateResult
    signals: Dict[str, Any]
    forensic_notice: str
