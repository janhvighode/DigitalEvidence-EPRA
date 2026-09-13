from typing import Optional, List
from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from database.database import get_db
from models.user import User
from utils.current_user import get_current_user

from schemas.investigator_dashboard import (
    InvestigatorDashboardStats,
    CaseRequiringAttentionItem,
    InvestigatorEvidenceStatusResponse,
    CaseStatusDistributionResponse,
    InvestigatorMyCasesPage,
    CaseOverviewResponse,
    CaseEvidenceSummaryResponse,
    InvestigatorEvidenceRepositoryPage,
    InvestigatorEvidenceDetailResponse,
    AnalysisProgressSummaryResponse,
    EvidenceAnalysisPage,
    EPRAPriorityDistributionResponse,
    PendingAnalysisResponse,
    InvestigatorAnalysisDetailResponse,
    RelationshipNodeDetailResponse
)
from schemas.relationship_graph import GraphResponse
from services.investigator_dashboard_service import (
    get_investigator_dashboard_stats,
    get_cases_requiring_attention,
    get_evidence_status,
    get_case_status_distribution,
    get_investigator_my_cases,
    get_investigator_case_overview,
    get_investigator_case_evidence_summary,
    get_investigator_case_evidence_repository,
    get_investigator_evidence_detail,
    get_investigator_evidence_file,
    get_investigator_analysis_summary,
    get_investigator_analysis_evidence_repository,
    get_investigator_epra_priority_distribution,
    get_investigator_pending_analysis,
    get_investigator_single_analysis_detail,
    get_investigator_relationship_view,
    get_investigator_relationship_node_detail
)


router = APIRouter(
    prefix="/investigator",
    tags=["Investigator Dashboard & Cases"]
)


def verify_investigator(current_user: User) -> User:
    """
    Enforces strict Investigator role authorization:
    - User must be authenticated
    - User must have role_id == 2 (Investigator)
    """
    if not current_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Authentication required"
        )

    if current_user.role_id != 2:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Investigator access required"
        )

    return current_user


# ==============================================================================
# 1. SUMMARY STATS (7 CARDS)
# ==============================================================================

@router.get(
    "/dashboard/stats",
    response_model=InvestigatorDashboardStats,
    summary="Get Investigator Dashboard Stats",
    description="Returns 7 genuine summary metrics strictly scoped to the authenticated investigator."
)
def fetch_dashboard_stats(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_dashboard_stats(db, current_user)


# ==============================================================================
# 2. CASES REQUIRING ATTENTION
# ==============================================================================

@router.get(
    "/dashboard/cases-requiring-attention",
    response_model=List[CaseRequiringAttentionItem],
    summary="Get Cases Requiring Attention",
    description="Returns assigned cases requiring immediate attention due to tampered evidence, critical EPRA, or high priority."
)
def fetch_cases_requiring_attention(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_cases_requiring_attention(db, current_user)


# ==============================================================================
# 3. EVIDENCE STATUS BREAKDOWN
# ==============================================================================

@router.get(
    "/dashboard/evidence-status",
    response_model=InvestigatorEvidenceStatusResponse,
    summary="Get Evidence Status Breakdown",
    description="Returns evidence integrity and analysis status metrics across all assigned cases."
)
def fetch_evidence_status(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_evidence_status(db, current_user)


# ==============================================================================
# 4. CASE STATUS DISTRIBUTION
# ==============================================================================

@router.get(
    "/dashboard/case-status-distribution",
    response_model=CaseStatusDistributionResponse,
    summary="Get Case Status Distribution",
    description="Returns case counts by status (Open, In Progress, Under Review, Closed) for assigned cases."
)
def fetch_case_status_distribution(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_case_status_distribution(db, current_user)


# ==============================================================================
# 5. MY ASSIGNED CASES
# ==============================================================================

@router.get(
    "/my-cases",
    response_model=InvestigatorMyCasesPage,
    summary="Get Investigator Assigned Cases",
    description="Returns paginated assigned cases for the investigator with search, status, priority, and cyber expert filters."
)
def fetch_investigator_my_cases(
    search: Optional[str] = Query(None, description="Search by case ID, title, or description"),
    status: Optional[str] = Query(None, description="Filter by status (Open, In Progress, Under Review, Closed)"),
    priority: Optional[str] = Query(None, description="Filter by priority (Low, Medium, High, Critical)"),
    cyber_expert_id: Optional[int] = Query(None, description="Filter by assigned Cyber Expert user ID"),
    start_date: Optional[str] = Query(None, description="Filter cases created on or after this ISO date"),
    end_date: Optional[str] = Query(None, description="Filter cases created on or before this ISO date"),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(10, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_my_cases(
        db=db,
        current_user=current_user,
        search=search,
        status=status,
        priority=priority,
        cyber_expert_id=cyber_expert_id,
        start_date=start_date,
        end_date=end_date,
        page=page,
        limit=limit
    )


# ==============================================================================
# 6. INVESTIGATOR VIEW CASE: CASE OVERVIEW
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/overview",
    response_model=CaseOverviewResponse,
    summary="Get Case Overview for Assigned Case",
    description="Returns case metadata, assigned investigator and cyber expert, key statistics, and genuine recent activity."
)
def fetch_case_overview(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_case_overview(
        db=db,
        case_identifier=case_id,
        current_user=current_user
    )


# ==============================================================================
# 7. INVESTIGATOR VIEW CASE: EVIDENCE MANAGEMENT SUMMARY
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/evidence-summary",
    response_model=CaseEvidenceSummaryResponse,
    summary="Get Evidence Summary Cards for Assigned Case",
    description="Returns selected-case counts for Total Evidence, Analyzed, Pending Analysis, and Integrity Issues."
)
def fetch_case_evidence_summary(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_case_evidence_summary(
        db=db,
        case_identifier=case_id,
        current_user=current_user
    )


# ==============================================================================
# 8. INVESTIGATOR VIEW CASE: EVIDENCE REPOSITORY LIST
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/evidence",
    response_model=InvestigatorEvidenceRepositoryPage,
    summary="Get Evidence Repository for Assigned Case",
    description="Returns paginated evidence repository items joined with EPRA and hash verification statuses with filters."
)
def fetch_case_evidence_repository(
    case_id: str,
    search: Optional[str] = Query(None, description="Search by evidence ID, file name, or current hash"),
    file_type: Optional[str] = Query(None, description="Filter by file type (Image, Video, Document, etc.)"),
    analysis_status: Optional[str] = Query(None, description="Filter by analysis status (COMPLETE, Pending)"),
    priority: Optional[str] = Query(None, description="Filter by priority (Critical, High, Medium, Low)"),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(10, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_case_evidence_repository(
        db=db,
        case_identifier=case_id,
        current_user=current_user,
        search=search if isinstance(search, str) else None,
        file_type=file_type if isinstance(file_type, str) else None,
        analysis_status=analysis_status if isinstance(analysis_status, str) else None,
        priority=priority if isinstance(priority, str) else None,
        page=page if isinstance(page, int) else 1,
        limit=limit if isinstance(limit, int) else 10
    )


# ==============================================================================
# 9. INVESTIGATOR VIEW CASE: SINGLE EVIDENCE DETAILS
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/evidence/{evidence_id}",
    response_model=InvestigatorEvidenceDetailResponse,
    summary="Get Single Evidence Comprehensive Forensic Details",
    description="Returns single evidence detail combining core Evidence, EvidenceHash verification, EPRAResult priorities/factors, and Deepak's EvidenceRecord metadata."
)
def fetch_evidence_detail(
    case_id: str,
    evidence_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_evidence_detail(
        db=db,
        case_identifier=case_id,
        evidence_identifier=evidence_id,
        current_user=current_user
    )


# ==============================================================================
# 10. INVESTIGATOR VIEW CASE: SECURE EVIDENCE DOWNLOAD
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/evidence/{evidence_id}/download",
    summary="Download Original Evidence File",
    description="Safely downloads the physical evidence file from storage with case isolation and path traversal prevention."
)
def download_evidence_file(
    case_id: str,
    evidence_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    file_path, file_name, media_type = get_investigator_evidence_file(
        db=db,
        case_identifier=case_id,
        evidence_identifier=evidence_id,
        current_user=current_user,
        for_preview=False
    )
    return FileResponse(
        path=str(file_path),
        filename=file_name,
        media_type=media_type,
        headers={"Content-Disposition": f'attachment; filename="{file_name}"'}
    )


# ==============================================================================
# 11. INVESTIGATOR VIEW CASE: SECURE EVIDENCE PREVIEW
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/evidence/{evidence_id}/preview",
    summary="Preview Evidence File",
    description="Streams previewable evidence file (images, PDFs, text, supported media) inline with authorization checks."
)
def preview_evidence_file(
    case_id: str,
    evidence_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    file_path, file_name, media_type = get_investigator_evidence_file(
        db=db,
        case_identifier=case_id,
        evidence_identifier=evidence_id,
        current_user=current_user,
        for_preview=True
    )
    return FileResponse(
        path=str(file_path),
        media_type=media_type,
        headers={"Content-Disposition": f'inline; filename="{file_name}"'}
    )


# ==============================================================================
# 12. INVESTIGATOR VIEW CASE: ANALYSIS PROGRESS SUMMARY
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/analysis-progress/summary",
    response_model=AnalysisProgressSummaryResponse,
    summary="Get Analysis Progress Summary",
    description="Returns genuine case-level EPRA metrics (total evidence, analyzed, pending, partial, high/critical, progress percentage)."
)
def fetch_analysis_progress_summary(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_analysis_summary(
        db=db,
        case_identifier=case_id,
        current_user=current_user
    )


# ==============================================================================
# 13. INVESTIGATOR VIEW CASE: ANALYSIS PROGRESS EVIDENCE REPOSITORY
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/analysis-progress/evidence",
    response_model=EvidenceAnalysisPage,
    summary="Get Analysis Progress Evidence Repository",
    description="Returns paginated evidence analysis items with priority, EPRA score, rank, pending inputs, and filters."
)
def fetch_analysis_progress_evidence(
    case_id: str,
    search: Optional[str] = Query(None, description="Search by evidence ID or file name"),
    file_type: Optional[str] = Query(None, description="Filter by file type (Image, Video, Document, etc.)"),
    analysis_status: Optional[str] = Query(None, description="Filter by analysis status (COMPLETE, PARTIAL / PENDING INPUTS, Pending)"),
    priority: Optional[str] = Query(None, description="Filter by priority (Critical, High, Medium, Low, Very Low)"),
    page: int = Query(1, ge=1, description="Page number"),
    limit: int = Query(10, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_analysis_evidence_repository(
        db=db,
        case_identifier=case_id,
        current_user=current_user,
        search=search if isinstance(search, str) else None,
        file_type=file_type if isinstance(file_type, str) else None,
        analysis_status=analysis_status if isinstance(analysis_status, str) else None,
        priority=priority if isinstance(priority, str) else None,
        page=page if isinstance(page, int) else 1,
        limit=limit if isinstance(limit, int) else 10
    )


# ==============================================================================
# 14. INVESTIGATOR VIEW CASE: EPRA PRIORITY DISTRIBUTION
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/analysis-progress/priority-distribution",
    response_model=EPRAPriorityDistributionResponse,
    summary="Get EPRA Priority Distribution",
    description="Returns priority distribution counts (Critical, High, Medium, Low, Very Low) for analyzed evidence in the case."
)
def fetch_epra_priority_distribution(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_epra_priority_distribution(
        db=db,
        case_identifier=case_id,
        current_user=current_user
    )


# ==============================================================================
# 15. INVESTIGATOR VIEW CASE: PENDING ANALYSIS ITEMS
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/analysis-progress/pending",
    response_model=PendingAnalysisResponse,
    summary="Get Pending Analysis Items",
    description="Returns list of evidence items awaiting complete analysis (Pending or Partial with pending inputs)."
)
def fetch_pending_analysis(
    case_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_pending_analysis(
        db=db,
        case_identifier=case_id,
        current_user=current_user
    )


# ==============================================================================
# 16. INVESTIGATOR VIEW CASE: SINGLE EVIDENCE ANALYSIS DETAIL
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/analysis-progress/evidence/{evidence_id}",
    response_model=InvestigatorAnalysisDetailResponse,
    summary="Get Single Evidence Analysis Detail",
    description="Returns single evidence EPRA risk factors, score, priority, rank, pending inputs, and status read-only."
)
def fetch_single_analysis_detail(
    case_id: str,
    evidence_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_single_analysis_detail(
        db=db,
        case_identifier=case_id,
        evidence_identifier=evidence_id,
        current_user=current_user
    )


# ==============================================================================
# 17. INVESTIGATOR VIEW CASE: RELATIONSHIP VIEW GRAPH
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/relationship-view",
    response_model=GraphResponse,
    summary="Get Case Relationship View Graph",
    description="Returns case relationship graph nodes (Evidence, Possible Entity, Device, Case) and edges (links, SHA-256 duplicates, CBIR similarity)."
)
def fetch_relationship_view(
    case_id: str,
    node_type: Optional[str] = Query(None, description="Filter by node type (Evidence, Possible Entity, Device, Case)"),
    relationship_type: Optional[str] = Query(None, description="Filter by relationship type (LINKED_TO, SUSPECT_INVOLVED, DEVICE_LINK, VERIFIED_DUPLICATE_SHA256, CBIR_VISUAL_SIMILARITY)"),
    priority: Optional[str] = Query(None, description="Filter evidence nodes by EPRA priority (Critical, High, Medium, Low)"),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_relationship_view(
        db=db,
        case_identifier=case_id,
        current_user=current_user,
        node_type=node_type if isinstance(node_type, str) else None,
        relationship_type=relationship_type if isinstance(relationship_type, str) else None,
        priority=priority if isinstance(priority, str) else None
    )


# ==============================================================================
# 18. INVESTIGATOR VIEW CASE: RELATIONSHIP NODE DETAIL
# ==============================================================================

@router.get(
    "/my-cases/{case_id}/relationship-view/nodes/{node_id}",
    response_model=RelationshipNodeDetailResponse,
    summary="Get Case Relationship Node Detail",
    description="Returns deep inspection properties for a node (Evidence with EPRA, Possible Entity, Device, Case) and connected edges."
)
def fetch_relationship_node_detail(
    case_id: str,
    node_id: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    verify_investigator(current_user)
    return get_investigator_relationship_node_detail(
        db=db,
        case_identifier=case_id,
        node_id=node_id,
        current_user=current_user
    )


