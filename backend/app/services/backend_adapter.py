"""
External Backend Adapter & Data Contracts for Member 5.

Defines the clean boundary interface for consuming:
- Case data (ID, title, crime type, status, assignment)
- Evidence records with controlled file access
- Existing baseline and current SHA-256 hashes (passed through, never recalculated)
- Verification statuses (Verified, Tampered, Pending, Unknown, Error)
- Suspect records and EPRA analysis results
- External custody and audit events

Provides:
1. BackendAdapter abstract base class
2. SharedBackendAdapter for production / runtime integration
3. MockBackendProvider for isolated, deterministic test fixtures
"""
from abc import ABC, abstractmethod
from datetime import datetime, timezone
from typing import Optional, List, Dict, Any, Tuple, BinaryIO
from pathlib import Path
from pydantic import BaseModel, Field


# ==============================================================================
# 1. Typed Data Contracts
# ==============================================================================

class CaseData(BaseModel):
    case_id: str
    case_title: Optional[str] = None
    crime_type: Optional[str] = None
    status: Optional[str] = None  # None unless explicitly supplied by source
    assigned_on: Optional[datetime] = None
    assigned_by: Optional[str] = None
    investigator_id: Optional[str] = None
    investigator_name: Optional[str] = None
    investigator_role: Optional[str] = None
    department: Optional[str] = None


class EvidenceItem(BaseModel):
    """
    Evidence item representation provided by the backend adapter.
    Internal file_path is NEVER exposed directly in public API responses.
    """
    evidence_id: str  # External string identifier (e.g., "EV-101", "1", "IMG_001")
    external_source: str = "shared_backend"  # Source system identity
    case_id: str
    original_filename: str
    file_type: str = "FILE"
    mime_type: Optional[str] = None
    file_size_bytes: int = 0
    file_path: Optional[str] = None  # Controlled internal storage reference only
    uploaded_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    created_at_source: Optional[str] = None
    modified_at: Optional[datetime] = None
    modified_at_source: Optional[str] = None
    accessed_at: Optional[datetime] = None
    accessed_at_source: Optional[str] = None
    # Existing hash values supplied by the backend — NEVER recalculated by Member 5
    original_sha256: Optional[str] = None
    current_sha256: Optional[str] = None
    verification_status: str = "Unknown"  # "Verified", "Tampered", "Pending", "Unknown", "Error"
    verification_timestamp: Optional[datetime] = None
    verification_source: Optional[str] = None
    verification_notes: Optional[str] = None
    retrieved_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class SuspectRecord(BaseModel):
    suspect_id: Optional[str] = None
    name: str
    role_or_relation: Optional[str] = None
    externally_supplied_ranking: Optional[int] = None
    linked_evidence_ids: List[str] = Field(default_factory=list)
    notes: Optional[str] = None
    status: Optional[str] = "Identified"


class EPRAAnalysisResult(BaseModel):
    """
    Downstream EPRA prioritization analysis result.
    Preserves measured/pending status, provenance, and missing-input reasons.
    """
    analysis_id: Optional[str] = None
    case_id: str
    evidence_id: str
    priority_score: Optional[float] = None
    priority_rank: Optional[int] = None
    category: Optional[str] = None
    status: str = "PENDING"  # "MEASURED", "PENDING", "UNAVAILABLE", "NOT_EVALUATED"
    missing_input_reason: Optional[str] = None
    provenance_source: Optional[str] = None
    algorithm_version: Optional[str] = None
    evaluated_at: Optional[datetime] = None
    notes: Optional[str] = None
    raw_metrics: Optional[Dict[str, Any]] = None


class ExternalCustodyEvent(BaseModel):
    """
    Custody handling event imported from external backend.
    external_event_id is used for idempotent deduplication.
    """
    external_event_id: str  # Stable external identity
    case_id: str
    evidence_id: str
    event_type: str  # "ACQUISITION", "UPLOAD", "HASH_GENERATED", "TRANSFER", "ACCESS", "REPORT"
    title: str
    description: Optional[str] = None
    timestamp: datetime
    actor_id: Optional[str] = None
    actor_name: str
    actor_role: Optional[str] = None
    is_system_action: bool = False
    outcome: str = "SUCCESS"
    source_reference: Optional[str] = None


# ==============================================================================
# 2. Canonical Status Mapping
# ==============================================================================

def map_backend_verification_status(raw_status: Optional[str]) -> str:
    """
    Map various external backend status representations into standard Member 5 display values:
    'Verified', 'Tampered', 'Pending', 'Unknown', 'Error'.
    Never assumes missing status or empty hash means Verified.
    """
    if not raw_status:
        return "Unknown"

    norm = raw_status.strip().lower()
    if norm in ("verified", "match", "valid", "intact", "unaltered"):
        return "Verified"
    elif norm in ("tampered", "mismatch", "modified", "corrupted", "altered"):
        return "Tampered"
    elif norm in ("pending", "in_progress", "processing", "queued", "pending_verification"):
        return "Pending"
    elif norm in ("error", "failed", "unreadable"):
        return "Error"
    elif norm in ("unknown", "unverified", "not_verified", "not_checked"):
        return "Unknown"
    return "Unknown"


# ==============================================================================
# 3. Backend Adapter Interface
# ==============================================================================

class BackendAdapter(ABC):
    """
    Abstract interface for connecting Member 5 to the shared integrated backend.
    """

    @property
    @abstractmethod
    def is_mocked(self) -> bool:
        """Returns True if this provider is an isolated mock for test fixtures."""
        pass

    @property
    @abstractmethod
    def is_connected(self) -> bool:
        """Returns True if a live connection to the external backend is active."""
        pass

    @abstractmethod
    def get_case(self, case_id: str) -> Optional[CaseData]:
        pass

    @abstractmethod
    def list_evidence(self, case_id: str) -> List[EvidenceItem]:
        pass

    @abstractmethod
    def get_evidence(self, evidence_id: str, case_id: Optional[str] = None) -> Optional[EvidenceItem]:
        pass

    @abstractmethod
    def get_evidence_file_stream(self, evidence_id: str) -> Optional[Tuple[BinaryIO, str, int]]:
        """Controlled file access: returns (file_stream, mime_type, size_bytes)."""
        pass

    @abstractmethod
    def get_suspects(self, case_id: str) -> List[SuspectRecord]:
        pass

    @abstractmethod
    def get_epra_analysis(self, case_id: str) -> List[EPRAAnalysisResult]:
        pass

    @abstractmethod
    def get_external_events(self, case_id: str, evidence_id: Optional[str] = None) -> List[ExternalCustodyEvent]:
        pass


# ==============================================================================
# 4. Production Shared Backend Adapter (Integration Pending Fallback)
# ==============================================================================

class SharedBackendAdapter(BackendAdapter):
    """
    Production adapter. Without a verified live shared backend endpoint and contract,
    it returns an explicit integration-pending state and does not claim a live connection.
    Consumes local synchronized cache where available.
    """

    def __init__(self, base_url: Optional[str] = None, api_key: Optional[str] = None):
        self.base_url = base_url
        self.api_key = api_key
        # Never claim connected without verifying a live contract endpoint.
        self._connected = False
        self.connection_status = "INTEGRATION_PENDING"

    @property
    def is_mocked(self) -> bool:
        return False

    @property
    def is_connected(self) -> bool:
        return False

    def get_case(self, case_id: str) -> Optional[CaseData]:
        # Without live backend connection, do not fabricate case status or details
        return None

    def list_evidence(self, case_id: str) -> List[EvidenceItem]:
        return []

    def get_evidence(self, evidence_id: str, case_id: Optional[str] = None) -> Optional[EvidenceItem]:
        return None

    def get_evidence_file_stream(self, evidence_id: str) -> Optional[Tuple[BinaryIO, str, int]]:
        return None

    def get_suspects(self, case_id: str) -> List[SuspectRecord]:
        return []

    def get_epra_analysis(self, case_id: str) -> List[EPRAAnalysisResult]:
        return []

    def get_external_events(self, case_id: Optional[str] = None, evidence_id: Optional[str] = None) -> List[ExternalCustodyEvent]:
        return []


# ==============================================================================
# 5. Mock Backend Provider for Isolated Test Fixtures
# ==============================================================================

class MockBackendProvider(BackendAdapter):
    """
    Isolated test provider. Explicitly marked as is_mocked=True.
    Used by test fixtures to verify Member 5 features without claiming live backend integration.
    """

    def __init__(self):
        self._cases: Dict[str, CaseData] = {}
        self._evidence: Dict[str, EvidenceItem] = {}
        self._suspects: Dict[str, List[SuspectRecord]] = {}
        self._epra: Dict[str, List[EPRAAnalysisResult]] = {}
        self._events: Dict[str, List[ExternalCustodyEvent]] = {}
        self._file_contents: Dict[str, bytes] = {}

    @property
    def is_mocked(self) -> bool:
        return True

    @property
    def is_connected(self) -> bool:
        return True

    def register_case(self, case: CaseData):
        self._cases[case.case_id] = case

    def register_evidence(self, evidence: EvidenceItem, file_bytes: Optional[bytes] = None):
        self._evidence[str(evidence.evidence_id)] = evidence
        if file_bytes is not None:
            self._file_contents[str(evidence.evidence_id)] = file_bytes
        elif evidence.file_path and Path(evidence.file_path).exists():
            try:
                self._file_contents[str(evidence.evidence_id)] = Path(evidence.file_path).read_bytes()
            except Exception:
                pass

    def register_suspects(self, case_id: str, suspects: List[SuspectRecord]):
        self._suspects[case_id] = suspects

    def register_epra_analysis(self, case_id: str, results: List[EPRAAnalysisResult]):
        self._epra[case_id] = results

    def register_events(self, case_id: str, events: List[ExternalCustodyEvent]):
        self._events[case_id] = events

    def get_case(self, case_id: str) -> Optional[CaseData]:
        return self._cases.get(case_id, None)

    def list_evidence(self, case_id: str) -> List[EvidenceItem]:
        return [ev for ev in self._evidence.values() if ev.case_id == case_id]

    def get_evidence(self, evidence_id: str, case_id: Optional[str] = None) -> Optional[EvidenceItem]:
        ev = self._evidence.get(str(evidence_id))
        if ev and case_id and ev.case_id != case_id:
            return None
        return ev

    def get_evidence_file_stream(self, evidence_id: str) -> Optional[Tuple[BinaryIO, str, int]]:
        content = self._file_contents.get(str(evidence_id))
        if content is None:
            ev = self.get_evidence(evidence_id)
            if ev and ev.file_path and Path(ev.file_path).exists():
                path = Path(ev.file_path)
                return open(path, "rb"), "application/octet-stream", path.stat().st_size
            return None
        import io
        stream = io.BytesIO(content)
        mime = "application/octet-stream"
        ev = self.get_evidence(evidence_id)
        if ev:
            if ev.file_type.lower() in ("jpeg", "jpg"):
                mime = "image/jpeg"
            elif ev.file_type.lower() == "png":
                mime = "image/png"
            elif ev.file_type.lower() == "pdf":
                mime = "application/pdf"
        return stream, mime, len(content)

    def get_suspects(self, case_id: str) -> List[SuspectRecord]:
        return self._suspects.get(case_id, [])

    def get_epra_analysis(self, case_id: str) -> List[EPRAAnalysisResult]:
        return self._epra.get(case_id, [])

    def get_external_events(self, case_id: Optional[str] = None, evidence_id: Optional[str] = None) -> List[ExternalCustodyEvent]:
        if case_id and case_id in self._events:
            events = self._events[case_id]
        elif not case_id:
            events = [e for ev_list in self._events.values() for e in ev_list]
        else:
            events = self._events.get(case_id, [])
        if evidence_id:
            events = [e for e in events if str(e.evidence_id) == str(evidence_id)]
        return events


# Global singleton adapter instance
_active_adapter: BackendAdapter = SharedBackendAdapter()


def get_backend_adapter() -> BackendAdapter:
    global _active_adapter
    return _active_adapter


def set_backend_adapter(adapter: BackendAdapter):
    global _active_adapter
    _active_adapter = adapter
