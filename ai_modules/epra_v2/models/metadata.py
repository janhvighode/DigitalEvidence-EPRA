"""
metadata.py

Defines the Metadata model used throughout the EPRA V2 engine.

This model represents a single piece of digital evidence and stores
all metadata extracted during forensic analysis.

This is the central data model shared across all EPRA modules.
"""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class Metadata:
    """
    Represents metadata associated with a single evidence file.
    """

    # ---------------------------------------------------------
    # Basic File Information
    # ---------------------------------------------------------

    file_name: str
    extension: str
    mime_type: str
    size: int

    # ---------------------------------------------------------
    # File Location
    # ---------------------------------------------------------

    absolute_path: str
    parent_directory: str

    # ---------------------------------------------------------
    # File Timestamps
    # ---------------------------------------------------------

    created_time: Optional[datetime] = None
    modified_time: Optional[datetime] = None
    accessed_time: Optional[datetime] = None

    # ---------------------------------------------------------
    # Ownership Information
    # ---------------------------------------------------------

    owner: Optional[str] = None

    # ---------------------------------------------------------
    # Evidence Classification
    # ---------------------------------------------------------

    evidence_type: Optional[str] = None

    # ---------------------------------------------------------
    # Integrity Information
    # ---------------------------------------------------------

    hash_algorithm: Optional[str] = None
    hash_value: Optional[str] = None

    # ---------------------------------------------------------
    # Investigation Information
    # ---------------------------------------------------------

    case_id: Optional[str] = None
    evidence_id: Optional[str] = None

    # ---------------------------------------------------------
    # Duplicate Information
    # ---------------------------------------------------------

    duplicate_id: Optional[str] = None

    # ---------------------------------------------------------
    # Evidence Collection Information
    # (Member 5)
    # ---------------------------------------------------------

    collection_device: Optional[str] = None

    collected_by: Optional[str] = None

    collection_time: Optional[datetime] = None

    # NEW
    evidence_source: Optional[str] = None
    # Laptop
    # Mobile
    # USB
    # Cloud
    # Email Server
    # CCTV
    # External HDD

    acquisition_method: Optional[str] = None
    # Disk Imaging
    # Logical Acquisition
    # Physical Acquisition
    # Live Acquisition
    # Memory Dump

    # ---------------------------------------------------------
    # Evidence Access Information
    # (Member 5 → Windows Artefacts)
    # ---------------------------------------------------------

    last_accessed_by: Optional[str] = None

    device_name: Optional[str] = None

    access_action: Optional[str] = None
    # OPEN
    # COPY
    # MOVE
    # DELETE
    # MODIFY
    # RENAME

    access_source: Optional[str] = None
    # Windows Event Log
    # Prefetch
    # Jump List
    # LNK
    # MFT
    # USN Journal
    # Shellbags
    # Registry

    access_count: int = 0

    access_timeline: list = field(default_factory=list)

    # ---------------------------------------------------------
    # Chain of Custody
    # (Member 5)
    # ---------------------------------------------------------

    chain_of_custody: list = field(default_factory=list)

    # ---------------------------------------------------------
    # Future Investigation Tags
    # ---------------------------------------------------------

    tags: list[str] = field(default_factory=list)

    notes: str = ""