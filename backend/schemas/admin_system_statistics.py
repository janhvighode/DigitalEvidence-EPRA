"""
Pydantic Schemas for Administrator -> System Statistics.
Provides typed request and response contracts for all aggregated statistics endpoints.
Strictly separates Case Priority from EPRA Evidence Priority.
"""
from datetime import date, datetime
from typing import Dict, List, Optional
from pydantic import BaseModel, Field


# =====================================================================
# EPRA STATISTICS SCHEMAS
# =====================================================================

class EPRAStatisticsResponse(BaseModel):
    """Aggregated statistics for EPRA (Evidence Prioritization & Risk Assessment)."""
    coverage_percentage: float = Field(..., description="Unique applicable evidence with completed EPRA analysis / total evidence * 100")
    total_evidence: int = Field(..., description="Total applicable evidence items in Administrator's Cyber Cell")
    analyzed_evidence: int = Field(..., description="Evidence items that have at least one EPRA analysis record")
    completed_analysis: int = Field(..., description="Evidence items with analysis_status == 'COMPLETE'")
    partial_analysis: int = Field(..., description="Evidence items with analysis_status == 'PARTIAL / PENDING INPUTS'")
    pending_analysis: int = Field(..., description="Evidence items without completed EPRA analysis")
    average_epra_score: Optional[float] = Field(None, description="Average EPRA score on 0-100 scale (null if no analyzed evidence)")
    highest_score: Optional[float] = Field(None, description="Maximum EPRA score on 0-100 scale (null if no analyzed evidence)")
    lowest_score: Optional[float] = Field(None, description="Minimum EPRA score on 0-100 scale (null if no analyzed evidence)")
    priority_distribution: Dict[str, int] = Field(
        ...,
        description="Evidence distribution by latest EPRA priority (CRITICAL, HIGH, MEDIUM, LOW, VERY LOW, PENDING)"
    )


# =====================================================================
# CBIR STATISTICS SCHEMAS
# =====================================================================

class CBIRStatisticsResponse(BaseModel):
    """Aggregated statistics for Content-Based Image Retrieval."""
    total_comparisons: int = Field(..., description="Total image candidate comparisons evaluated")
    cases_with_cbir: int = Field(..., description="Distinct cases with CBIR comparisons")
    images_analyzed: int = Field(..., description="Unique image evidence items analyzed in comparisons")
    exact_duplicates: int = Field(..., description="Comparisons flagged as cryptographic SHA-256 exact duplicates")
    visual_matches: int = Field(..., description="Meaningful visual resemblance comparisons (excluding No Significant Visual Match and Weak Visual Resemblance)")
    match_rate: float = Field(..., description="Visual matches / total comparisons * 100 (0.0 if empty)")
    average_visual_similarity: Optional[float] = Field(None, description="Average visual similarity score (0.0 to 1.0, null if empty)")
    highest_visual_similarity: Optional[float] = Field(None, description="Maximum visual similarity score (0.0 to 1.0, null if empty)")
    classification_distribution: Dict[str, int] = Field(
        ...,
        description="Breakdown by classification category"
    )
    latest_analysis_at: Optional[str] = Field(None, description="Timestamp of latest CBIR analysis")


# =====================================================================
# INVESTIGATOR PERFORMANCE SCHEMAS
# =====================================================================

class InvestigatorPerformanceItem(BaseModel):
    """Operational workload and case metrics for a single investigator."""
    investigator_id: int
    investigator_name: str
    assigned_cases: int
    active_cases: int
    completed_cases: int
    evidence_count: int
    completion_ratio: float = Field(..., description="completed_cases / assigned_cases * 100 (0.0 if 0 assigned)")
    latest_case_activity: Optional[str] = None


class InvestigatorStatisticsResponse(BaseModel):
    """Branch-wide investigator operational metrics."""
    total_investigators: int = Field(..., description="Total active investigators in Cyber Cell")
    active_investigators: int = Field(..., description="Investigators with at least 1 assigned case")
    average_assigned_cases: float = Field(..., description="Average caseload across active investigators")
    top_completion_ratio: float = Field(..., description="Highest case completion percentage among branch investigators")
    investigators: List[InvestigatorPerformanceItem]


# =====================================================================
# CASE TREND SCHEMAS
# =====================================================================

class CaseTrendBucket(BaseModel):
    """Period-based case metrics for timeline charting."""
    period: str = Field(..., description="Period identifier, e.g. '2026-09'")
    created_cases: int = Field(..., description="Cases registered in this period")
    closed_cases: int = Field(..., description="Cases transitioned to Closed in this period")
    active_cases: int = Field(..., description="Active open caseload in this period")


class CaseTrendResponse(BaseModel):
    """Trend analysis for case intake and closure over time."""
    cases_this_month: int = Field(..., description="Cases created in the current calendar month")
    total_cases_in_period: int = Field(..., description="Total cases created within requested date range")
    trends: List[CaseTrendBucket]


# =====================================================================
# PRIORITY ANALYSIS SCHEMAS
# =====================================================================

class PriorityAnalysisResponse(BaseModel):
    """Strictly separated distributions for Case Triage Priority and EPRA Evidence Priority."""
    case_priority_distribution: Dict[str, int] = Field(
        ...,
        description="Case triage priority distribution (Critical, High, Medium, Low)"
    )
    evidence_epra_priority_distribution: Dict[str, int] = Field(
        ...,
        description="Individual evidence EPRA priority distribution (CRITICAL, HIGH, MEDIUM, LOW, VERY LOW, PENDING)"
    )


# =====================================================================
# FORENSIC MODULE SUMMARY SCHEMAS
# =====================================================================

class ForensicSummaryResponse(BaseModel):
    """System-level forensic metrics aggregated across Cyber Cell cases."""
    integrity_verified: int = Field(..., description="Evidence items verified with matching SHA-256 hash")
    integrity_tampered: int = Field(..., description="Evidence items flagged as tampered or hash mismatch")
    integrity_pending: int = Field(..., description="Evidence items pending hash verification")
    total_hashes: int = Field(..., description="Total evidence hashes recorded")
    metadata_processed: int = Field(..., description="Evidence records with processing_status == 'PROCESSED'")
    metadata_pending: int = Field(..., description="Evidence records pending metadata extraction")
    total_metadata_records: int = Field(..., description="Total metadata records captured")
    suspect_entities_count: int = Field(..., description="Suspect entities identified in Cyber Cell cases")
    cases_with_suspects: int = Field(..., description="Cases with ranked suspect entities")
    total_evidence_links: int = Field(..., description="Relational links between evidence, suspects, and devices")
    cases_with_links: int = Field(..., description="Cases with relationship links")
    reports_generated: int = Field(..., description="Finalized forensic technical reports generated")
    cases_with_reports: int = Field(..., description="Cases with finalized technical reports")


# =====================================================================
# OVERALL EXECUTIVE SUMMARY SCHEMA
# =====================================================================

class AdminSystemStatisticsSummaryResponse(BaseModel):
    """Consolidated executive dashboard summary for the Administrator."""
    # EPRA Highlights
    epra_coverage_percentage: float
    total_evidence: int
    epra_completed_evidence: int
    pending_epra_analysis: int
    average_epra_score: Optional[float] = None

    # CBIR Highlights
    cbir_total_comparisons: int
    cbir_exact_duplicates: int
    cbir_visual_matches: int
    cbir_match_rate: float

    # Case Highlights
    cases_this_month: int
    total_cases: int
    active_cases: int
    closed_cases: int

    # Investigator Highlights
    total_investigators: int
    active_investigators: int
    top_investigator_completion_ratio: float

    # Optional Forensic Module Summary
    forensic_summary: ForensicSummaryResponse
