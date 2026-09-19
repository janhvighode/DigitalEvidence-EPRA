from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field


class TransferInitiateRequest(BaseModel):
    evidence_id: str
    case_id: Optional[str] = None
    sender_name: Optional[str] = None
    sender_id: Optional[str] = None
    sender_role: Optional[str] = "Cyber Expert"
    recipient_name: str
    recipient_id: Optional[str] = None
    recipient_role: Optional[str] = "Cyber Expert"
    reason_or_remarks: Optional[str] = None


class TransferReceiveRequest(BaseModel):
    recipient_name: Optional[str] = None
    recipient_id: Optional[str] = None
    recipient_role: Optional[str] = "Cyber Expert"
    department: Optional[str] = None
    location: Optional[str] = None
    remarks: Optional[str] = None


class CurrentCustodyUpdateRequest(BaseModel):
    department: Optional[str] = None
    location: Optional[str] = None
    remarks: Optional[str] = None
    actor_name: Optional[str] = None
    actor_id: Optional[str] = None
    current_holder_id: Optional[str] = None
    current_holder_name: Optional[str] = None
    current_holder_role: Optional[str] = None
    custody_status: Optional[str] = None


class CustodyAccessRequest(BaseModel):
    purpose: Optional[str] = "Forensic analysis inspection"


class CustodyTimelineEvent(BaseModel):
    event_id: int
    external_event_id: Optional[str] = None
    evidence_id: Optional[str] = None
    case_id: Optional[str] = None
    event_type: Optional[str] = None
    title: Optional[str] = None
    description: Optional[str] = None
    timestamp: Optional[str] = None
    timestamp_formatted: Optional[str] = None
    recorded_at: Optional[str] = None
    actor_id: Optional[str] = None
    actor_name: Optional[str] = None
    actor_role: Optional[str] = None
    is_system_action: bool = False
    outcome: str = "SUCCESS"
    transfer_reference: Optional[str] = None
    transfer_sender: Optional[str] = None
    transfer_recipient: Optional[str] = None


class CustodyTimelineResponse(BaseModel):
    case_id: Optional[str] = None
    evidence_id: Optional[str] = None
    filter_applied: str = "ALL"
    total_events: int
    events: List[CustodyTimelineEvent]


class CurrentCustodyResponse(BaseModel):
    evidence_id: str
    case_id: Optional[str] = None
    current_holder_id: Optional[str] = None
    current_holder_name: Optional[str] = None
    current_holder_role: Optional[str] = None
    department: Optional[str] = None
    assigned_on: Optional[str] = None
    assigned_on_formatted: Optional[str] = None
    last_accessed: Optional[str] = None
    last_accessed_formatted: Optional[str] = None
    location: Optional[str] = None
    remarks: Optional[str] = None
    custody_status: Optional[str] = None
    pending_recipient_id: Optional[str] = None
    pending_recipient_name: Optional[str] = None
    updated_at: Optional[str] = None


class CustodySummaryResponse(BaseModel):
    case_id: Optional[str] = None
    evidence_id: Optional[str] = None
    total_events: int
    handlers_count: int
    transfers_count: int
    completed_transfers: int
    pending_transfers: int
    first_handled: Optional[str] = None
    first_handled_formatted: Optional[str] = None
    current_status: Optional[str] = None


class TransferItemResponse(BaseModel):
    row_number: int
    transfer_reference: str
    from_identity: str
    to_identity: str
    initiated_at: Optional[str] = None
    received_at: Optional[str] = None
    date_time_display: str
    status: str
    remarks: Optional[str] = None


class TransferHistoryResponse(BaseModel):
    case_id: Optional[str] = None
    evidence_id: Optional[str] = None
    total: int
    page: int
    page_size: int
    transfers: List[TransferItemResponse]


class EvidenceCustodyDetailResponse(BaseModel):
    case_id: int
    evidence_id: str
    file_name: str
    original_filename: Optional[str] = None
    file_type: str
    canonical_type: str
    evidence_type: str
    mime_type: Optional[str] = None
    file_size: int
    file_size_bytes: int
    created_at: Optional[str] = None
    upload_timestamp: Optional[str] = None
    uploaded_at: Optional[str] = None
    uploaded_by: Optional[str] = None
    added_by: Optional[str] = None
    original_sha256: Optional[str] = None
    original_hash: Optional[str] = None
    current_hash: Optional[str] = None
    sha256_hash: Optional[str] = None
    integrity_status: Optional[str] = None
    integrity_verification_status: Optional[str] = None
    current_custodian: Optional[str] = None
    last_accessed: Optional[str] = None
    status: Optional[str] = None
    evidence_status: Optional[str] = None
    preview_url: Optional[str] = None
    download_url: Optional[str] = None
    summary: Optional[Dict[str, Any]] = None
    current_custody: Optional[Dict[str, Any]] = None
    timeline: Optional[List[Dict[str, Any]]] = None
    transfers: Optional[Dict[str, Any]] = None
