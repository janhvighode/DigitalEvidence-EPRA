import sys
from pathlib import Path
from typing import Any, Dict, List, Optional
from datetime import datetime

# Ensure project root and backend dir are in sys.path
root_dir = Path(__file__).resolve().parent.parent.parent
if str(root_dir) not in sys.path:
    sys.path.insert(0, str(root_dir))
backend_dir = Path(__file__).resolve().parent.parent
if str(backend_dir) not in sys.path:
    sys.path.insert(0, str(backend_dir))

from fastapi import HTTPException
from sqlalchemy.orm import Session, joinedload
from sqlalchemy import or_, func

from models.case import Case
from models.user import User
from models.evidence import Evidence
from models.epra_result import EPRAResult
from models.possible_entity import PossibleEntity, PossibleEntityEvidenceLink
from services.epra_service import get_case_or_404, authorize_cyber_expert_case_access, process_case_epra
from services.timeline_service import create_timeline_event
from schemas.possible_entity import (
    RankedEntityResponse,
    EntityDetailResponse,
    EntitySummaryOverview,
    LinkedEvidenceSummary,
    ProcessEntitiesResponse,
)

# Reuse Janhvi's EPRA V2 suspect/entity ranking logic
from ai_modules.epra_v2.models.evidence import Evidence as JanhviEvidence
from ai_modules.epra_v2.models.metadata import Metadata as JanhviMetadata
from ai_modules.epra_v2.intelligence.relationship_analyzer import RelationshipAnalyzer
from ai_modules.epra_v2.ranking.suspect_ranker import SuspectRanker


def map_entity_type(identifier: str) -> str:
    """
    Maps an identifier string to a standard API entity type category:
    EMAIL, IP ADDRESS, CRYPTO WALLET, ACCOUNT ID, or OTHER.
    """
    ident = identifier.strip()
    if "@" in ident:
        return "EMAIL"
    if RelationshipAnalyzer.IPV4_REGEX.match(ident):
        return "IP ADDRESS"
    if ident.startswith("0x") and len(ident) == 42:
        return "CRYPTO WALLET"
    if ident.startswith("bc1") or (
        len(ident) >= 26 and ident[0] in "13" and not ident.isdigit()
    ):
        return "CRYPTO WALLET"
    if ident.upper().startswith(("ACC", "ACCT", "IBAN")):
        return "ACCOUNT ID"
    return "OTHER"


def resolve_evidence_file_path(file_path: Optional[str]) -> str:
    """
    Safely resolves the evidence file path across different execution working directories.
    """
    if not file_path:
        return ""

    p = Path(file_path)
    if p.is_file():
        return str(p.resolve())

    # Try backend_dir relative
    b_p = backend_dir / p
    if b_p.is_file():
        return str(b_p.resolve())

    # Try root_dir relative
    r_p = root_dir / p
    if r_p.is_file():
        return str(r_p.resolve())

    return str(file_path)


def build_ranked_entity_response(entity: PossibleEntity) -> RankedEntityResponse:
    """
    Derives linked_evidence_ids from the relational link table and builds RankedEntityResponse.
    """
    linked_ids = []
    if entity.evidence_links:
        for link in entity.evidence_links:
            if link.evidence and link.evidence.evidence_id:
                linked_ids.append(link.evidence.evidence_id)

    return RankedEntityResponse(
        id=entity.id,
        suspect_id=entity.suspect_id,
        suspect_name=entity.suspect_name,
        entity_type=entity.entity_type,
        rank=entity.rank,
        total_epra_score=entity.total_epra_score,
        linked_evidence_count=entity.linked_evidence_count,
        linked_evidence_ids=linked_ids,
        confidence_score=entity.confidence_score,
        created_at=entity.created_at,
        processed_at=entity.processed_at,
    )


def process_case_suspect_ranking(
    db: Session,
    case: Case,
    current_user: User
) -> Dict[str, Any]:
    """
    Executes transaction-safe, idempotent Suspect / Entity Ranking for a case:
    1. Ensures case has evidence records and EPRA risk scores are up-to-date.
    2. Builds Janhvi Evidence items and extracts genuine actor identifiers safely.
    3. Executes Janhvi's SuspectRanker to compute scores and ranks:
       Total EPRA Score = SUM(linked evidence EPRA scores) DESC, tie-break suspect_name ASC.
    4. Upserts into possible_entities and synchronizes possible_entity_evidence_links in a single DB transaction:
       - Updates existing matching entities
       - Inserts new entities
       - Updates evidence links
       - Removes only stale ranking/link rows for THIS SAME CASE
    5. Records a timeline event.
    6. Returns execution status, summary, and ranked entities.
    """
    evidence_records = (
        db.query(Evidence)
        .filter(Evidence.case_id == case.id)
        .order_by(Evidence.id.asc())
        .all()
    )

    if not evidence_records:
        empty_summary = EntitySummaryOverview(
            case_id=case.case_id,
            total_suspects_entities=0,
            email_addresses=0,
            ip_addresses=0,
            wallet_addresses=0,
            account_ids=0,
            other_entities=0,
            highest_score=0.0,
            lowest_score=0.0,
            average_score=0.0,
            top_entities=[],
            entity_type_distribution={},
            last_processed_at=datetime.now(),
        )
        return {
            "message": "No evidence records found for this case",
            "case_id": case.case_id,
            "total_entities_identified": 0,
            "processed_at": datetime.now(),
            "summary": empty_summary,
            "ranked_entities": [],
            "limitations_note": "No evidence files available in this case.",
        }

    # Verify existing EPRA results; if missing, run EPRA first so evidence has real EPRA scores
    epra_records = (
        db.query(EPRAResult)
        .filter(EPRAResult.case_id == case.id)
        .all()
    )
    if not epra_records or len(epra_records) < len(evidence_records):
        process_case_epra(db, case, current_user)
        epra_records = (
            db.query(EPRAResult)
            .filter(EPRAResult.case_id == case.id)
            .all()
        )

    epra_score_map = {rec.evidence_id: rec.epra_score for rec in epra_records}

    # Map DB evidence into Janhvi's model and safely extract genuine content
    janhvi_evidence_list: List[JanhviEvidence] = []
    skipped_unreadable_count = 0

    for ev in evidence_records:
        resolved_path = resolve_evidence_file_path(ev.file_path)
        ext = Path(ev.file_name).suffix.lower()

        meta = JanhviMetadata(
            file_name=ev.file_name,
            extension=ext,
            mime_type="application/octet-stream",
            size=ev.file_size or 0,
            absolute_path=resolved_path,
            parent_directory=str(Path(resolved_path).parent) if resolved_path else "",
            case_id=str(case.case_id),
            evidence_id=str(ev.evidence_id),
            evidence_type=ev.file_type,
        )

        j_ev = JanhviEvidence(metadata=meta)
        j_ev.epra_score = epra_score_map.get(ev.id, 0.0)

        # Attach reference to original DB id for robust relational link creation
        j_ev.db_evidence_id = ev.id
        j_ev.db_evidence_uid = ev.evidence_id

        # Safely extract text content (supports .eml, .txt, .log, .csv, .json, .xml)
        # Binary files without pre-supplied text are skipped safely without fabricating identifiers
        text_content = RelationshipAnalyzer.extract_text_content(j_ev)
        if not text_content:
            skipped_unreadable_count += 1

        # Process actor identifiers and isolate transactions (never fabricating human names)
        RelationshipAnalyzer.process(j_ev, demo_mode=False)
        janhvi_evidence_list.append(j_ev)

    # Correlate and rank suspect entities via Janhvi's EPRA V2 engine
    suspect_candidates = RelationshipAnalyzer.generate_suspect_candidates(
        janhvi_evidence_list,
        demo_mode=False
    )
    ranked_suspects = SuspectRanker.rank(suspect_candidates)

    # Database synchronization inside transaction
    ev_by_uid = {ev.evidence_id: ev for ev in evidence_records}
    ev_by_id = {ev.id: ev for ev in evidence_records}

    try:
        existing_entities = (
            db.query(PossibleEntity)
            .filter(PossibleEntity.case_id == case.id)
            .all()
        )
        existing_map = {e.suspect_id: e for e in existing_entities}
        new_suspect_ids = {s.suspect_id for s in ranked_suspects}

        saved_entities: List[PossibleEntity] = []

        for suspect in ranked_suspects:
            norm_type = map_entity_type(suspect.suspect_name)

            if suspect.suspect_id in existing_map:
                ent = existing_map[suspect.suspect_id]
                ent.suspect_name = suspect.suspect_name
                ent.entity_type = norm_type
                ent.rank = suspect.rank
                ent.total_epra_score = suspect.total_epra_score
                ent.linked_evidence_count = len(suspect.evidence_list)
                ent.confidence_score = suspect.confidence_score
                ent.processed_at = func.now()
            else:
                ent = PossibleEntity(
                    case_id=case.id,
                    suspect_id=suspect.suspect_id,
                    suspect_name=suspect.suspect_name,
                    entity_type=norm_type,
                    rank=suspect.rank,
                    total_epra_score=suspect.total_epra_score,
                    linked_evidence_count=len(suspect.evidence_list),
                    confidence_score=suspect.confidence_score,
                )
                db.add(ent)
                db.flush()

            # Determine target evidence DB IDs for this suspect
            target_ev_db_ids = set()
            for j_ev in suspect.evidence_list:
                ev_uid = getattr(j_ev.metadata, "evidence_id", None)
                if ev_uid and ev_uid in ev_by_uid:
                    target_ev_db_ids.add(ev_by_uid[ev_uid].id)
                elif hasattr(j_ev, "db_evidence_id") and j_ev.db_evidence_id in ev_by_id:
                    target_ev_db_ids.add(j_ev.db_evidence_id)

            # Synchronize relational links in possible_entity_evidence_links
            existing_links = (
                db.query(PossibleEntityEvidenceLink)
                .filter(PossibleEntityEvidenceLink.entity_id == ent.id)
                .all()
            )
            existing_ev_ids = {link.evidence_id: link for link in existing_links}

            # Insert missing links
            for ev_id in target_ev_db_ids - set(existing_ev_ids.keys()):
                db.add(PossibleEntityEvidenceLink(entity_id=ent.id, evidence_id=ev_id))

            # Remove stale links for this entity
            for ev_id, link in existing_ev_ids.items():
                if ev_id not in target_ev_db_ids:
                    db.delete(link)

            saved_entities.append(ent)

        # Remove stale entities for THIS CASE ONLY
        for suspect_id, stale_ent in existing_map.items():
            if suspect_id not in new_suspect_ids:
                db.query(PossibleEntityEvidenceLink).filter(
                    PossibleEntityEvidenceLink.entity_id == stale_ent.id
                ).delete(synchronize_session=False)
                db.delete(stale_ent)

        db.commit()

        # Log timeline event
        create_timeline_event(
            db=db,
            case_id=case.id,
            event="Suspect / Entity Ranking generated",
            performed_by=current_user.id,
            performed_by_role="Cyber Expert",
        )

    except Exception as e:
        db.rollback()
        raise HTTPException(
            status_code=500,
            detail=f"Failed to process suspect ranking: {str(e)}"
        )

    # Re-query saved entities with eager loading for clean serialization
    final_entities = (
        db.query(PossibleEntity)
        .options(
            joinedload(PossibleEntity.evidence_links).joinedload(
                PossibleEntityEvidenceLink.evidence
            )
        )
        .filter(PossibleEntity.case_id == case.id)
        .order_by(PossibleEntity.rank.asc())
        .all()
    )

    ranked_responses = [build_ranked_entity_response(e) for e in final_entities]
    summary = get_case_possible_entities_summary(db, case)

    limitations_note = None
    if skipped_unreadable_count > 0:
        limitations_note = (
            f"{skipped_unreadable_count} evidence item(s) did not have direct text-readable "
            f"formats (.eml, .txt, .log, .csv, .json) or extracted text and were safely skipped "
            f"without fabricating identifiers."
        )

    return {
        "message": "Suspect / Entity Ranking analysis completed successfully",
        "case_id": case.case_id,
        "total_entities_identified": len(ranked_responses),
        "processed_at": datetime.now(),
        "summary": summary,
        "ranked_entities": ranked_responses,
        "limitations_note": limitations_note,
    }


def get_case_ranked_possible_entities(
    db: Session,
    case: Case,
    limit: Optional[int] = None,
    entity_type: Optional[str] = None
) -> List[RankedEntityResponse]:
    """
    Returns ranked possible entities for a case ordered by rank ascending.
    Optionally filters by entity_type and applies a limit.
    """
    query = (
        db.query(PossibleEntity)
        .options(
            joinedload(PossibleEntity.evidence_links).joinedload(
                PossibleEntityEvidenceLink.evidence
            )
        )
        .filter(PossibleEntity.case_id == case.id)
    )

    if entity_type:
        query = query.filter(PossibleEntity.entity_type == entity_type.upper())

    query = query.order_by(PossibleEntity.rank.asc())

    if limit and limit > 0:
        query = query.limit(limit)

    entities = query.all()
    return [build_ranked_entity_response(e) for e in entities]


def get_case_possible_entities_summary(
    db: Session,
    case: Case
) -> EntitySummaryOverview:
    """
    Computes dynamic overview and distribution of possible entities for a case.
    """
    entities = (
        db.query(PossibleEntity)
        .options(
            joinedload(PossibleEntity.evidence_links).joinedload(
                PossibleEntityEvidenceLink.evidence
            )
        )
        .filter(PossibleEntity.case_id == case.id)
        .order_by(PossibleEntity.rank.asc())
        .all()
    )

    if not entities:
        return EntitySummaryOverview(
            case_id=case.case_id,
            total_suspects_entities=0,
            email_addresses=0,
            ip_addresses=0,
            wallet_addresses=0,
            account_ids=0,
            other_entities=0,
            highest_score=0.0,
            lowest_score=0.0,
            average_score=0.0,
            top_entities=[],
            entity_type_distribution={},
            last_processed_at=None,
        )

    scores = [e.total_epra_score for e in entities]
    highest_score = round(max(scores), 2)
    lowest_score = round(min(scores), 2)
    average_score = round(sum(scores) / len(scores), 2)

    distribution: Dict[str, int] = {}
    email_cnt = 0
    ip_cnt = 0
    wallet_cnt = 0
    account_cnt = 0
    other_cnt = 0

    for e in entities:
        t = e.entity_type
        distribution[t] = distribution.get(t, 0) + 1
        if t == "EMAIL":
            email_cnt += 1
        elif t == "IP ADDRESS":
            ip_cnt += 1
        elif t == "CRYPTO WALLET":
            wallet_cnt += 1
        elif t == "ACCOUNT ID":
            account_cnt += 1
        else:
            other_cnt += 1

    top_entities = [build_ranked_entity_response(e) for e in entities[:5]]
    last_processed = max([e.processed_at for e in entities if e.processed_at], default=None)

    return EntitySummaryOverview(
        case_id=case.case_id,
        total_suspects_entities=len(entities),
        email_addresses=email_cnt,
        ip_addresses=ip_cnt,
        wallet_addresses=wallet_cnt,
        account_ids=account_cnt,
        other_entities=other_cnt,
        highest_score=highest_score,
        lowest_score=lowest_score,
        average_score=average_score,
        top_entities=top_entities,
        entity_type_distribution=distribution,
        last_processed_at=last_processed,
    )


def get_possible_entity_detail(
    db: Session,
    case: Case,
    entity_identifier: str | int
) -> EntityDetailResponse:
    """
    Retrieves full detail of a specific entity including linked evidence items,
    their EPRA scores, and priorities.
    """
    ident_str = str(entity_identifier).strip()

    query = (
        db.query(PossibleEntity)
        .options(
            joinedload(PossibleEntity.evidence_links).joinedload(
                PossibleEntityEvidenceLink.evidence
            )
        )
        .filter(PossibleEntity.case_id == case.id)
    )

    if ident_str.isdigit():
        entity = query.filter(
            or_(
                PossibleEntity.id == int(ident_str),
                PossibleEntity.suspect_id == ident_str,
            )
        ).first()
    else:
        entity = query.filter(
            or_(
                PossibleEntity.suspect_id == ident_str,
                PossibleEntity.suspect_name.ilike(ident_str),
            )
        ).first()

    if not entity:
        raise HTTPException(
            status_code=404,
            detail=f"Possible entity '{entity_identifier}' not found in case '{case.case_id}'"
        )

    # Collect linked evidence items with EPRA scores
    linked_evidence_items: List[LinkedEvidenceSummary] = []
    linked_ids: List[str] = []

    for link in entity.evidence_links:
        ev = link.evidence
        if not ev:
            continue

        linked_ids.append(ev.evidence_id)
        epra_rec = (
            db.query(EPRAResult)
            .filter(EPRAResult.evidence_id == ev.id)
            .first()
        )

        linked_evidence_items.append(
            LinkedEvidenceSummary(
                evidence_id=ev.evidence_id,
                file_name=ev.file_name,
                file_type=ev.file_type,
                epra_score=epra_rec.epra_score if epra_rec else None,
                priority=epra_rec.priority if epra_rec else None,
            )
        )

    return EntityDetailResponse(
        id=entity.id,
        suspect_id=entity.suspect_id,
        suspect_name=entity.suspect_name,
        entity_type=entity.entity_type,
        rank=entity.rank,
        total_epra_score=entity.total_epra_score,
        linked_evidence_count=entity.linked_evidence_count,
        linked_evidence_ids=linked_ids,
        confidence_score=entity.confidence_score,
        created_at=entity.created_at,
        processed_at=entity.processed_at,
        linked_evidence=linked_evidence_items,
    )
