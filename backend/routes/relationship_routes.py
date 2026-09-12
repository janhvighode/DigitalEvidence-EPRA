from typing import List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status, Query
from sqlalchemy.orm import Session

from database.database import get_db
from utils.current_user import get_current_user
from models.user import User
from schemas.relationship_graph import (
    GraphResponse,
    GraphSummary,
    DuplicatePairResponse,
    CreateLinkRequest,
    EvidenceLinkResponse,
    CBIRQueryResponse
)
from services.relationship_graph_service import RelationshipGraphService

relationship_router = APIRouter(
    prefix="/cases/{case_id}/relationships",
    tags=["Relationship Analysis & Graph"]
)


@relationship_router.get(
    "/graph",
    response_model=GraphResponse,
    summary="Get Case Relationship Graph",
    description="Returns dynamic nodes and edges representing genuine evidence, suspect, device, and duplicate relationships for the case."
)
def get_relationship_graph(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        return RelationshipGraphService.get_relationship_graph(db, case_id, current_user)
    except PermissionError as pe:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(pe))
    except FileNotFoundError as fe:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(fe))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to generate relationship graph: {str(e)}")


@relationship_router.get(
    "/summary",
    response_model=GraphSummary,
    summary="Get Case Relationship Summary Cards",
    description="Returns aggregate entity counts, duplicate counts, and relationship metrics for dashboard cards."
)
def get_relationship_summary(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        return RelationshipGraphService.get_relationship_summary(db, case_id, current_user)
    except PermissionError as pe:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(pe))
    except FileNotFoundError as fe:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(fe))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to fetch relationship summary: {str(e)}")


@relationship_router.get(
    "/duplicates",
    response_model=List[DuplicatePairResponse],
    summary="Get Verified Duplicate Evidence Pairs",
    description="Returns exact bitwise duplicates within the case derived strictly from verified SHA-256 integrity checks."
)
def get_duplicate_pairs(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        return RelationshipGraphService.get_duplicate_pairs(db, case_id, current_user)
    except PermissionError as pe:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(pe))
    except FileNotFoundError as fe:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(fe))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to fetch duplicate pairs: {str(e)}")


@relationship_router.post(
    "/links",
    response_model=EvidenceLinkResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Record Custom Evidence Link",
    description="Records an explicit investigative link between evidence and a suspect or device (adapted from Trisha's evidence_linker)."
)
def create_evidence_link(
    case_id: str,
    link_data: CreateLinkRequest,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        return RelationshipGraphService.create_evidence_link(db, case_id, link_data, current_user)
    except PermissionError as pe:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(pe))
    except FileNotFoundError as fe:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(fe))
    except ValueError as ve:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(ve))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to create evidence link: {str(e)}")


@relationship_router.get(
    "/links",
    response_model=List[EvidenceLinkResponse],
    summary="List Custom Evidence Links",
    description="Lists all explicit investigative links recorded for the case."
)
def list_evidence_links(
    case_id: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        return RelationshipGraphService.list_evidence_links(db, case_id, current_user)
    except PermissionError as pe:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(pe))
    except FileNotFoundError as fe:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(fe))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to list evidence links: {str(e)}")


@relationship_router.delete(
    "/links/{link_id}",
    summary="Delete Custom Evidence Link",
    description="Deletes a custom evidence link belonging to the case."
)
def delete_evidence_link(
    case_id: str,
    link_id: int,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        return RelationshipGraphService.delete_evidence_link(db, case_id, link_id, current_user)
    except PermissionError as pe:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(pe))
    except FileNotFoundError as fe:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(fe))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to delete evidence link: {str(e)}")


@relationship_router.get(
    "/cbir/{evidence_id}",
    response_model=CBIRQueryResponse,
    summary="Execute CBIR Visual Comparison",
    description="Executes case-restricted visual comparison for an evidence item using Trisha's CBIR pipeline."
)
def run_cbir_query(
    case_id: str,
    evidence_id: str,
    top_k: int = Query(5, ge=1, le=50),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    try:
        return RelationshipGraphService.run_cbir_query(db, case_id, evidence_id, current_user, top_k)
    except PermissionError as pe:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail=str(pe))
    except FileNotFoundError as fe:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(fe))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Failed to execute CBIR query: {str(e)}")
