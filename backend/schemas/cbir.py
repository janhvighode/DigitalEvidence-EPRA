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
    """
    Robust CBIR Comparison Request Schema.
    Accepts case_id and query_evidence_id, while also accepting common
    aliases such as evidence_id or image_id to prevent HTTP 422 errors.
    """
    case_id: Optional[Any] = Field(None, description="Case identifier")
    query_evidence_id: Optional[Any] = Field(None, description="Query evidence ID or numeric ID")
    evidence_id: Optional[Any] = Field(None, description="Alias for query_evidence_id")
    image_id: Optional[Any] = Field(None, description="Alias for query_evidence_id")
    classification: Optional[str] = Field(default=None, description="Optional classification filter")
    min_visual_similarity: Optional[float] = Field(default=0.0, ge=0.0, le=1.0, description="Minimum visual similarity threshold (0.0 to 1.0)")
    top_k: Optional[int] = Field(default=50, ge=1, le=100, description="Maximum number of candidate matches to return")

    @property
    def resolved_query_evidence_id(self) -> Optional[str]:
        val = self.query_evidence_id or self.evidence_id or self.image_id
        return str(val).strip() if val is not None else None


class CBIRCandidateResult(BaseModel):
    """Full candidate result item matching approved 18-column/field design."""
    case_id: Any
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
    confidence: Optional[str] = None
    confidence_level: Optional[str] = None
    verification_required: bool
    recommendation: Optional[str] = None
    investigation_recommendation: Optional[str] = None
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
    status: Optional[str] = "Success"
    message: Optional[str] = None
    case_id: Any
    query_evidence_id: str
    query_filename: str
    total_case_evidence: Optional[int] = 0
    eligible_image_count: Optional[int] = 0
    candidates_compared: Optional[int] = 0
    summary: Optional[CBIRSearchSummary] = None
    results: List[CBIRCandidateResult]
    cards: Optional[List[Dict[str, Any]]] = []
    forensic_disclaimer: Optional[str] = None
    forensic_notice: Optional[str] = None


class CBIRCandidateDetailResponse(BaseModel):
    """Detailed candidate comparison view for 'View Details' modal."""
    candidate: CBIRCandidateResult
    signals: Dict[str, Any]
    forensic_notice: str


class CBIRCaseEligibleImagesResponse(BaseModel):
    """List of eligible image evidence items in a case available for CBIR comparison."""
    case_id: str
    total_case_evidence: int
    eligible_image_count: int
    eligible_images: List[Dict[str, Any]]


class CaseSearchRequest(BaseModel):
    """Case evidence search request."""
    query_text: Optional[str] = Field(default="", description="Search query string")
    case_id: Optional[str] = Field(None, description="Case ID if not in path")
    top_k: Optional[int] = Field(10, description="Max results")
    search_mode: Optional[str] = Field("text", description="Search mode: 'text', 'context', or 'all'")
    max_hops: Optional[int] = Field(2, description="Max hops for graph context traversal")
    query_evidence_id: Optional[str] = Field(default=None, description="Query evidence ID for image or hybrid search")
    query_image_path: Optional[str] = Field(default=None, description="Query image path for image or hybrid search")


class CaseSearchResponse(BaseModel):
    """Structured case evidence search response."""
    status: str
    message: Optional[str] = None
    case_id: Optional[str] = None
    search_query: str
    search_box_label: Optional[str] = "Search evidence in this case..."
    results_count: int
    results: List[Dict[str, Any]]
    ranked_evidence: Optional[List[Dict[str, Any]]] = []
    forensic_notice: Optional[str] = None
