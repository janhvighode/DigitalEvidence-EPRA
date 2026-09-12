from typing import List, Optional
from fastapi import APIRouter, Depends, Query, status
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.epra import (
    EPRARunRequest,
    EPRARunResponse,
    EPRASummaryResponse,
    RankedEvidenceResponse,
    EvidenceEPRADetailResponse
)
from services.epra_service import (
    authorize_cyber_expert_case_access,
    process_case_epra,
    get_case_epra_summary,
    get_case_ranked_evidence,
    get_evidence_epra_detail
)


router = APIRouter(
    prefix="/cases",
    tags=["EPRA - Evidence Prioritization & Risk Analysis"]
)


# ============================================================
# 1. RUN EPRA ANALYSIS
# ============================================================

@router.post(
    "/{case_id}/epra/process",
    response_model=EPRARunResponse,
    status_code=status.HTTP_200_OK
)
def run_case_epra_analysis(
    case_id: str,
    request: Optional[EPRARunRequest] = None,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Executes Janhvi's EPRA analysis on all evidence items belonging strictly to the authorized case.
    - Validates JWT and requires current_user.role_id == 3 (Cyber Expert).
    - Enforces case assignment: Case.cyber_expert_id == current_user.id.
    - Integrates Member 5 SHA-256 integrity and Member 3 CBIR/Semantic inputs.
    - Preserves IMAGE SI as null and 'PENDING' when Member 3 CBIR score is missing.
    - Ranks all evidence and stores results in TiDB.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)

    external_inputs = request.external_inputs if request else None
    demo_mode = request.demo_mode if request else False

    return process_case_epra(
        db=db,
        case=case,
        current_user=current_user,
        external_inputs=external_inputs,
        demo_mode=demo_mode
    )


# ============================================================
# 2. CASE EPRA SUMMARY & METRICS
# ============================================================

@router.get(
    "/{case_id}/epra/summary",
    response_model=EPRASummaryResponse
)
def fetch_case_epra_summary(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns case-wise EPRA summary metrics derived dynamically from stored results:
    - total_evidence, critical, high, medium, low, very_low, pending_analysis
    - score_distribution breakdown
    - top 5 ranked evidence items
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)
    return get_case_epra_summary(db, case)


# ============================================================
# 3. CASE RANKED EVIDENCE LIST
# ============================================================

@router.get(
    "/{case_id}/epra/evidence",
    response_model=List[RankedEvidenceResponse]
)
def fetch_case_ranked_evidence(
    case_id: str,
    limit: Optional[int] = Query(None, ge=1, description="Limit to top N records"),
    priority: Optional[str] = Query(None, description="Filter by priority (Critical, High, Medium, Low, Very Low)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns the prioritized evidence table for the selected case, sorted strictly by EPRA rank.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)
    return get_case_ranked_evidence(
        db=db,
        case=case,
        limit=limit,
        priority=priority
    )


# ============================================================
# 4. SINGLE EVIDENCE EPRA DETAIL
# ============================================================

@router.get(
    "/{case_id}/epra/evidence/{evidence_id}",
    response_model=EvidenceEPRADetailResponse
)
def fetch_evidence_epra_detail(
    case_id: str,
    evidence_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Returns comprehensive forensic detail, risk factors (AR, CI, BI, SI, II),
    IPI, EPRA score, priority, rank, and external integration pending reasons for a single evidence item.
    """
    case = authorize_cyber_expert_case_access(db, case_id, current_user)
    return get_evidence_epra_detail(
        db=db,
        case=case,
        evidence_identifier=evidence_id
    )
