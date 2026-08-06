from typing import List, Optional
from pydantic import BaseModel, Field
from datetime import datetime


class Evidence(BaseModel):
    """
    EPRA Evidence Model
    -------------------
    This model represents a single piece of digital evidence.
    It acts as the shared data model between all project modules.
    """

    # ==========================
    # 1. Identification
    # ==========================
    evidence_id: str
    case_id: str

    # ==========================
    # 2. File Information
    # ==========================
    file_name: str
    file_extension: str
    file_type: str
    mime_type: str
    file_size: int
    file_path: str

    # ==========================
    # 3. Metadata
    # ==========================
    created_at: Optional[datetime] = None
    modified_at: Optional[datetime] = None
    uploaded_at: datetime = Field(default_factory=datetime.now)

    uploaded_by: Optional[str] = None
    device_name: Optional[str] = None
    device_id: Optional[str] = None

    # ==========================
    # 4. Security
    # ==========================
    sha256_hash: Optional[str] = None

    integrity_verified: bool = False
    is_duplicate: bool = False
    duplicate_of: Optional[str] = None

    # ==========================
    # 5. CBIR Results
    # ==========================
    detected_objects: List[str] = Field(default_factory=list)
    ocr_text: Optional[str] = None
    similar_images: List[str] = Field(default_factory=list)
    image_similarity_score: float = 0.0
    # ==========================
    # 6. Intelligence Scores
    # ==========================
    authenticity_score: float = 0.0
    context_score: float = 0.0
    behaviour_score: float = 0.0
    semantic_score: float = 0.0
    investigative_score: float = 0.0

    # ==========================
    # 7. ADM Weights
    # ==========================
    authenticity_weight: float = 0.0
    context_weight: float = 0.0
    behaviour_weight: float = 0.0
    semantic_weight: float = 0.0
    investigative_weight: float = 0.0

    # ==========================
    # 8. Final Results
    # ==========================
    epra_score: float = 0.0
    priority_rank: Optional[int] = None

    # ==========================
    # 9. Suspect Information
    # ==========================
    linked_suspects: List[str] = Field(default_factory=list)

    # ==========================
    # 10. Explainability
    # ==========================
    decision_path: Optional[str] = None