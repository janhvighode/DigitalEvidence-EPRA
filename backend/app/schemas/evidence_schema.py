from typing import Optional, List, Any, Dict
from pydantic import BaseModel, Field


class SuspectRecord(BaseModel):
    suspect_id: Optional[str] = None
    name: str
    role_or_relation: Optional[str] = None
    externally_supplied_ranking: Optional[int] = None
    linked_evidence_ids: List[str] = Field(default_factory=list)
    notes: Optional[str] = None


class EvidenceItemSummary(BaseModel):
    evidence_id: str
    case_id: str
    original_filename: str
    file_type: str
    file_type_display: str
    mime_type: Optional[str] = None
    file_size_bytes: int
    file_size_formatted: str
    created_at: Optional[str] = None
    created_at_source: Optional[str] = None
    modified_at: Optional[str] = None
    modified_at_source: Optional[str] = None
    accessed_at: Optional[str] = None
    uploaded_at: Optional[str] = None
    investigator_name: Optional[str] = None
    # Existing hash values supplied by the backend
    original_sha256: Optional[str] = None
    current_sha256: Optional[str] = None
    verification_status: str  # "Verified", "Tampered", "Pending", "Unknown", "Error"
    verification_timestamp: Optional[str] = None
    verification_source: Optional[str] = None
    download_url: str
    preview_url: Optional[str] = None


class TransferInitiateRequest(BaseModel):
    evidence_id: str
    case_id: Optional[str] = None
    sender_name: str
    sender_id: Optional[str] = None
    sender_role: Optional[str] = "Investigator"
    recipient_name: str
    recipient_id: Optional[str] = None
    recipient_role: Optional[str] = "Cyber Expert"
    reason_or_remarks: Optional[str] = None


class TransferReceiveRequest(BaseModel):
    recipient_name: str
    recipient_id: Optional[str] = None
    recipient_role: Optional[str] = "Cyber Expert"
    department: Optional[str] = None
    location: Optional[str] = None
    remarks: Optional[str] = None


class CurrentCustodyUpdateRequest(BaseModel):
    department: Optional[str] = None
    location: Optional[str] = None
    remarks: Optional[str] = None
    actor_name: str = "Investigator"
    actor_id: Optional[str] = None


class DownstreamEvidenceItem(BaseModel):
    evidence_id: str
    case_id: str
    original_filename: str
    file_type: str
    mime_type: Optional[str] = None
    file_size_bytes: int
    upload_timestamp: Optional[str] = None
    baseline_hash: Optional[str] = None
    latest_current_hash: Optional[str] = None
    integrity_status: str  # "Verified", "Tampered", "Pending", "Unknown", "Error"
    latest_verification_timestamp: Optional[str] = None
    custody_events_count: int
    recent_custody_action: Optional[str] = None
    metadata: Dict[str, Any]


class DownstreamEPRAResponse(BaseModel):
    contract_version: str = "2.0.0"
    target_consumer: str = "Proposed EPRA Module Contract"
    case_id: str
    generated_at: str
    total_evidence_count: int
    evidence_summary: Dict[str, Any]
    suspect_availability: str = "NO_SUSPECT_INFORMATION_AVAILABLE"
    suspect_count: int = 0
    suspect_records: List[Dict[str, Any]] = Field(default_factory=list)
    evidence_records: List[DownstreamEvidenceItem]
    custody_trail: List[Dict[str, Any]]
    integration_notes: Dict[str, str]
