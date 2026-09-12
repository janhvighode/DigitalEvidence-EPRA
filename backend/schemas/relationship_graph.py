from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field


class GraphNode(BaseModel):
    id: str
    label: str
    node_type: str = Field(..., description="Evidence, Suspect, Device, or Case")
    category: Optional[str] = Field(None, description="IMAGE, PDF, VIDEO, EMAIL, IP ADDRESS, etc.")
    properties: Dict[str, Any] = Field(default_factory=dict)


class GraphEdge(BaseModel):
    id: str
    source: str
    target: str
    label: str
    relationship_type: str = Field(
        ...,
        description="EVIDENCE_SUSPECT_LINK, EVIDENCE_DEVICE_LINK, EXACT_DUPLICATE, CBIR_VISUAL_RELATIONSHIP, MANUAL_LINK"
    )
    similarity: Optional[float] = None
    confidence: Optional[str] = None
    investigative_status: Optional[str] = None
    properties: Optional[Dict[str, Any]] = None


class GraphSummary(BaseModel):
    case_id: str
    total_nodes: int
    total_edges: int
    evidence_count: int
    suspect_count: int
    device_count: int
    duplicate_pairs_count: int
    cbir_matches_count: int
    manual_links_count: int


class GraphResponse(BaseModel):
    status: str = "Success"
    case_id: str
    nodes: List[GraphNode]
    edges: List[GraphEdge]
    summary: GraphSummary
    forensic_notice: str = (
        "Graph connections are derived strictly from genuine database records, verified SHA-256 hashes, "
        "and investigative visual analysis. Visual similarities do not prove criminal identity or culpability."
    )


class DuplicatePairResponse(BaseModel):
    evidence_id_1: str
    evidence_id_2: str
    filename_1: str
    filename_2: str
    sha256_hash: str
    file_size_bytes: int
    verification_status: str
    relationship: str = "Exact Duplicate (SHA-256 Match)"


class CreateLinkRequest(BaseModel):
    evidence_id: str = Field(..., description="External or numeric evidence ID")
    suspect_name: Optional[str] = Field(None, description="Suspect identity / identifier")
    device_name: Optional[str] = Field(None, description="Device make / model / hardware identifier")
    relationship_type: Optional[str] = Field("MANUAL_LINK", description="Custom relationship label")
    notes: Optional[str] = Field(None, description="Investigator notes")


class EvidenceLinkResponse(BaseModel):
    id: int
    case_id: int
    evidence_id: int
    external_evidence_id: Optional[str] = None
    evidence_filename: Optional[str] = None
    suspect_name: Optional[str] = None
    device_name: Optional[str] = None
    relationship_type: str
    notes: Optional[str] = None
    created_at: Optional[str] = None


class CBIRMatchItem(BaseModel):
    evidence_id: str
    category: Optional[str] = None
    image: Optional[str] = None
    similarity: float
    semantic_score: float
    similarity_level: str
    status: str
    action: str


class CBIRQueryResponse(BaseModel):
    status: str
    case_id: str
    source_evidence: str
    total_case_evidence: int
    results_returned: int
    matches: List[CBIRMatchItem]
    relationships: List[Dict[str, Any]]
    forensic_notice: str
