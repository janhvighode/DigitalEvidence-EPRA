from typing import List, Optional, Dict, Any
from datetime import datetime
from pydantic import BaseModel, ConfigDict


class LinkedEvidenceSummary(BaseModel):
    evidence_id: str
    file_name: str
    file_type: str
    evidence_type: Optional[str] = None
    epra_score: Optional[float] = None
    priority: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class RankedEntityResponse(BaseModel):
    id: int
    suspect_id: str
    internal_entity_id: Optional[str] = None
    suspect_name: str
    entity_identifier: Optional[str] = None
    entity_type: str
    rank: int
    total_epra_score: float
    linked_evidence_count: int
    linked_evidence_ids: List[str] = []
    confidence_score: Optional[float] = None
    created_at: Optional[datetime] = None
    processed_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class EntityDetailResponse(BaseModel):
    id: int
    suspect_id: str
    internal_entity_id: Optional[str] = None
    suspect_name: str
    entity_identifier: Optional[str] = None
    entity_type: str
    rank: int
    total_epra_score: float
    linked_evidence_count: int
    linked_evidence_ids: List[str] = []
    confidence_score: Optional[float] = None
    created_at: Optional[datetime] = None
    processed_at: Optional[datetime] = None
    linked_evidence: List[LinkedEvidenceSummary] = []

    model_config = ConfigDict(from_attributes=True)


class EntitySummaryOverview(BaseModel):
    case_id: str
    total_suspects_entities: int
    email_addresses: int
    ip_addresses: int
    wallet_addresses: int
    account_ids: int
    other_entities: int
    highest_score: float
    lowest_score: float
    average_score: float
    top_entities: List[RankedEntityResponse] = []
    entity_type_distribution: Dict[str, int] = {}
    last_processed_at: Optional[datetime] = None


class ProcessEntitiesResponse(BaseModel):
    message: str
    case_id: str
    total_entities_identified: int
    processed_at: datetime
    summary: EntitySummaryOverview
    ranked_entities: List[RankedEntityResponse] = []
    limitations_note: Optional[str] = None
