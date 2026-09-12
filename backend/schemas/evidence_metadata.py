from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, ConfigDict


class MetadataSummaryResponse(BaseModel):
    case_id: str
    total_files: int
    total_size_bytes: int
    total_size_formatted: str
    distinct_file_types: int
    latest_upload: Optional[str] = None
    latest_upload_formatted: Optional[str] = None
    hash_recorded_count: int = 0
    verified_files_count: int = 0
    tampered_files_count: int = 0
    pending_verification_count: int = 0

    model_config = ConfigDict(from_attributes=True)


class MetadataTableItem(BaseModel):
    row_number: int
    evidence_id: str
    original_filename: str
    file_type: str
    file_type_display: str
    file_category: str
    size_bytes: int
    size_formatted: str
    created_at: Optional[str] = None
    created_at_display: str
    created_at_source: Optional[str] = None
    modified_at: Optional[str] = None
    modified_at_display: str
    modified_at_source: Optional[str] = None
    hash_status: str
    sha256_hash: Optional[str] = None
    has_preview: bool
    preview_url: Optional[str] = None
    download_url: str
    details_url: str

    model_config = ConfigDict(from_attributes=True)


class MetadataTableResponse(BaseModel):
    case_id: str
    total_items: int
    page: int
    page_size: int
    total_pages: int
    items: List[MetadataTableItem]

    model_config = ConfigDict(from_attributes=True)


class MetadataInfo(BaseModel):
    file_name: str
    file_type: str
    file_size: str
    created_at: Optional[str] = None
    created_at_display: str
    created_at_source: Optional[str] = None
    modified_at: Optional[str] = None
    modified_at_display: str
    modified_at_source: Optional[str] = None
    accessed_at: Optional[str] = None
    accessed_at_display: str
    accessed_at_source: Optional[str] = None
    uploaded_at: Optional[str] = None
    uploaded_at_display: str

    model_config = ConfigDict(from_attributes=True)


class HashInfo(BaseModel):
    sha256: Optional[str] = None
    current_sha256: Optional[str] = None
    verification_status: str
    verified_at: Optional[str] = None
    verification_source: Optional[str] = None
    verification_notes: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class FileProperties(BaseModel):
    extension: str
    mime_type: str
    mime_type_source: str
    is_image: bool
    dimensions: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    image_mode: Optional[str] = None
    color_space: Optional[str] = None
    image_support_note: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class EvidenceDetailResponse(BaseModel):
    evidence_id: str
    case_id: str
    filename: str
    file_type: str
    file_type_display: str
    file_category: str
    file_size: str
    file_size_bytes: int
    metadata_information: MetadataInfo
    hash_information: HashInfo
    file_properties: FileProperties
    download_url: str
    preview_url: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class MetadataExtractResponse(BaseModel):
    message: str
    case_id: str
    total_synchronized: int
    summary: MetadataSummaryResponse

    model_config = ConfigDict(from_attributes=True)
