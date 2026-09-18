# ============================================================
# Digital Evidence EPRA
# Module : Relationship Graph
# File   : case_graph_engine.py
# Purpose: Multi-entity, case-isolated forensic relationship graph
#          supporting all evidence types, devices, persons, and cases.
# ============================================================

import os
import sys
import sqlite3
import networkx as nx

CURRENT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.abspath(os.path.join(CURRENT_DIR, "..", ".."))
CBIR_DIR = os.path.abspath(os.path.join(PROJECT_ROOT, "ai_modules", "cbir"))

for path in [PROJECT_ROOT, CURRENT_DIR, CBIR_DIR]:
    if path not in sys.path:
        sys.path.insert(0, path)

from evidence_linker import get_case_links, connect_database as connect_graph_db
from feature_database import get_case_evidence
from metadata_adapter import MetadataAdapter


def classify_device_type(device_name):
    """
    Classify device into specific forensic type based on actual entity name.
    """
    if not device_name:
        return "Device"
    d_lower = str(device_name).lower()
    if any(k in d_lower for k in ["samsung", "iphone", "phone", "mobile", "galaxy", "pixel", "oneplus"]):
        return "Device: Mobile Phone"
    elif any(k in d_lower for k in ["laptop", "dell", "lenovo", "macbook", "thinkpad", "pc", "computer", "desktop"]):
        return "Device: Computer"
    return "Device"


def classify_evidence_type(category):
    """
    Map project category to standard forensic evidence entity type.
    """
    if not category:
        return "Evidence"
    cat_lower = str(category).lower()
    if "pdf" in cat_lower:
        return "Evidence: PDF"
    elif "video" in cat_lower or "cctv" in cat_lower:
        return "Evidence: Video"
    elif "audio" in cat_lower or "recording" in cat_lower:
        return "Evidence: Audio"
    elif "log" in cat_lower:
        return "Evidence: Log File"
    elif "text" in cat_lower:
        return "Evidence: Text File"
    elif "document" in cat_lower or "invoice" in cat_lower:
        return "Evidence: Document"
    elif "person" in cat_lower or "suspect" in cat_lower:
        return "Evidence: Person Photo"
    elif "crime_scene" in cat_lower or "scene" in cat_lower:
        return "Evidence: Crime Scene"
    elif "weapon" in cat_lower or "gun" in cat_lower:
        return "Evidence: Weapon"
    elif "vehicle" in cat_lower or "car" in cat_lower:
        return "Evidence: Vehicle"
    elif "mobile" in cat_lower or "phone" in cat_lower:
        return "Evidence: Mobile Device"
    elif "laptop" in cat_lower or "computer" in cat_lower:
        return "Evidence: Laptop Device"
    return f"Evidence: {category.capitalize()}"


def add_qualified_edge(graph, u, v, edge_data):
    """
    Safely add a relationship edge between u and v:
    - Deduplicates identical relationships (same u, v, relationship_type).
    - Preserves legitimately different relationship types between the same nodes
      in edge['parallel_relationships'].
    """
    u_str = str(u)
    v_str = str(v)
    if u_str == v_str:
        return

    rel_type = edge_data.get("relationship_type", edge_data.get("relationship", "ASSOCIATED_WITH"))
    edge_dict = dict(edge_data)

    if graph.has_edge(u_str, v_str):
        existing = graph.get_edge_data(u_str, v_str)
        existing_type = existing.get("relationship_type", existing.get("relationship"))
        if existing_type == rel_type:
            # Identical relationship type: update if higher confidence
            if float(edge_dict.get("confidence", 0.0)) > float(existing.get("confidence", 0.0)):
                existing.update(edge_dict)
            return

        # Parallel relationship between same nodes
        if "parallel_relationships" not in existing:
            first_rel = dict(existing)
            existing["parallel_relationships"] = [first_rel]

        if not any(pr.get("relationship_type") == rel_type for pr in existing["parallel_relationships"]):
            existing["parallel_relationships"].append(edge_dict)
    else:
        graph.add_edge(u_str, v_str, **edge_dict)


def build_case_relationship_graph(case_id, cbir_relationships=None, duplicate_relationships=None, **kwargs):
    """
    Construct a complete NetworkX relationship graph for the selected case.

    Parameters
    ----------
    case_id : str
        The case ID to isolate the graph to.
    cbir_relationships : list of dict, optional
        CBIR visual or cryptographic relationship records to merge into the graph.

    Returns
    -------
    nx.Graph
        A NetworkX Graph populated with typed nodes and qualified edges.
    """
    graph = nx.Graph()

    if not case_id:
        return graph

    case_id_str = str(case_id)

    # 1. Add Case Root Node
    case_details = MetadataAdapter.build_clean_node_details(
        case_id_str,
        {"type": "Case", "label": f"Case: {case_id_str}", "case_id": case_id_str}
    )
    graph.add_node(
        case_id_str,
        type="Case",
        label=f"Case: {case_id_str}",
        entity_id=case_id_str,
        node_details=case_details
    )

    # 2. Fetch all evidence items belonging strictly to this case
    case_evidence = get_case_evidence(case_id_str)

    for ev in case_evidence:
        ev_id = str(ev.get("evidence_id"))
        cat = ev.get("category", "General")
        ev_type = classify_evidence_type(cat)
        img_p = ev.get("image_path")
        fn = os.path.basename(img_p) if img_p else ev_id

        meta = MetadataAdapter.extract_file_metadata(
            img_p,
            fallback_info={
                "evidence_id": ev_id,
                "category": cat,
                "description": ev.get("description"),
                "filename": fn
            }
        )
        node_details = MetadataAdapter.build_clean_node_details(
            ev_id,
            {
                "type": ev_type,
                "label": ev_id,
                "image_path": img_p,
                "description": ev.get("description"),
                "metadata": meta,
                "case_id": case_id_str
            }
        )

        graph.add_node(
            ev_id,
            type=ev_type,
            category=cat,
            label=ev_id,
            image_path=img_p,
            filename=fn,
            sha256_hash=ev.get("sha256_hash"),
            description=ev.get("description"),
            metadata=meta,
            node_details=node_details
        )

        # Connect Evidence -> Case
        add_qualified_edge(
            graph,
            ev_id,
            case_id_str,
            {
                "relationship": "BELONGS_TO_CASE",
                "relationship_type": "BELONGS_TO_CASE",
                "confidence": 1.0,
                "source": "Case Registry",
                "status": "Confirmed Case Evidence",
                "verification_required": False,
                "investigative_status": "Confirmed Case Evidence",
                "case_id": case_id_str
            }
        )

    # 3. Fetch evidence links from relationship database
    links = get_case_links(case_id_str)

    for link in links:
        ev_id = str(link.get("evidence"))
        suspect = link.get("suspect")
        device = link.get("device")
        conf = float(link.get("confidence", 1.0))
        rel_type = link.get("relationship_type", "ASSOCIATED_WITH")
        ver_req = bool(link.get("verification_required", True))

        has_device = bool(device and str(device).strip() and str(device).lower() != "none")
        has_suspect = bool(suspect and str(suspect).strip() and str(suspect).lower() != "none")

        # Ensure evidence node exists
        if not graph.has_node(ev_id):
            meta = MetadataAdapter.extract_file_metadata(
                link.get("file_path") or link.get("image_path"),
                fallback_info={
                    "evidence_id": ev_id,
                    "category": link.get("evidence_type", "Evidence"),
                    "description": link.get("description"),
                    "filename": ev_id
                }
            )
            node_details = MetadataAdapter.build_clean_node_details(
                ev_id,
                {
                    "type": link.get("evidence_type", "Evidence"),
                    "label": ev_id,
                    "metadata": meta,
                    "case_id": case_id_str,
                    "source_device": str(device).strip() if has_device else None
                }
            )
            graph.add_node(
                ev_id,
                type=link.get("evidence_type", "Evidence"),
                label=ev_id,
                filename=ev_id,
                metadata=meta,
                node_details=node_details
            )
            add_qualified_edge(
                graph,
                ev_id,
                case_id_str,
                {
                    "relationship": "BELONGS_TO_CASE",
                    "relationship_type": "BELONGS_TO_CASE",
                    "confidence": 1.0,
                    "source": "Case Registry",
                    "status": "Confirmed Case Evidence",
                    "verification_required": False,
                    "investigative_status": "Confirmed Case Evidence",
                    "case_id": case_id_str
                }
            )

        if has_device and graph.has_node(ev_id):
            graph.nodes[ev_id]["source_device"] = str(device).strip()
            if "node_details" in graph.nodes[ev_id]:
                graph.nodes[ev_id]["node_details"]["source_device"] = str(device).strip()

        # Connect Evidence -> Device
        if has_device:
            device_str = str(device).strip()
            dev_type = classify_device_type(device_str)
            dev_details = MetadataAdapter.build_clean_node_details(
                device_str,
                {
                    "type": dev_type,
                    "label": device_str,
                    "user": str(suspect).strip() if has_suspect else None,
                    "case_id": case_id_str
                }
            )
            if not graph.has_node(device_str):
                graph.add_node(
                    device_str,
                    type=dev_type,
                    label=device_str,
                    entity_id=device_str,
                    owner=str(suspect).strip() if has_suspect else None,
                    node_details=dev_details
                )

            dev_rel_type = rel_type if rel_type in ["STORED_ON_DEVICE", "EXTRACTED_FROM", "RECOVERED_FROM_DEVICE"] else "STORED_ON_DEVICE"
            add_qualified_edge(
                graph,
                ev_id,
                device_str,
                {
                    "relationship": dev_rel_type,
                    "relationship_type": dev_rel_type,
                    "confidence": conf,
                    "source": "Case Database Link",
                    "status": "Candidate Hardware Link" if ver_req else "Verified Hardware Link",
                    "verification_required": ver_req,
                    "investigative_status": "Candidate Hardware Link" if ver_req else "Verified Hardware Link",
                    "case_id": case_id_str
                }
            )

        # Connect Device -> Suspect (Device Ownership / Usage)
        if has_device and has_suspect:
            device_str = str(device).strip()
            suspect_str = str(suspect).strip()
            if not graph.has_node(suspect_str):
                person_details = MetadataAdapter.build_clean_node_details(
                    suspect_str,
                    {
                        "type": "Person / Suspect",
                        "label": suspect_str,
                        "case_id": case_id_str
                    }
                )
                graph.add_node(
                    suspect_str,
                    type="Person / Suspect",
                    label=suspect_str,
                    entity_id=suspect_str,
                    node_details=person_details
                )
            if not graph.has_edge(device_str, suspect_str):
                add_qualified_edge(
                    graph,
                    device_str,
                    suspect_str,
                    {
                        "relationship": "OWNED_OR_USED_BY",
                        "relationship_type": "OWNED_OR_USED_BY",
                        "confidence": conf,
                        "source": "Case Database Link",
                        "status": "Candidate Device User (Verification Required)",
                        "verification_required": True,
                        "investigative_status": "Candidate Device User",
                        "case_id": case_id_str
                    }
                )

        # Connect Evidence -> Suspect (Direct link if explicitly requested or depiction/association)
        if has_suspect:
            suspect_str = str(suspect).strip()
            if not graph.has_node(suspect_str):
                person_details = MetadataAdapter.build_clean_node_details(
                    suspect_str,
                    {
                        "type": "Person / Suspect",
                        "label": suspect_str,
                        "case_id": case_id_str
                    }
                )
                graph.add_node(
                    suspect_str,
                    type="Person / Suspect",
                    label=suspect_str,
                    entity_id=suspect_str,
                    node_details=person_details
                )

            # Support explicit DEPICTS_PERSON only when backed by actual link/record data
            if rel_type == "DEPICTS_PERSON":
                add_qualified_edge(
                    graph,
                    ev_id,
                    suspect_str,
                    {
                        "relationship": "DEPICTS_PERSON",
                        "relationship_type": "DEPICTS_PERSON",
                        "confidence": conf,
                        "source": "Case Database Link",
                        "status": "Depiction Record (Verification Required)" if ver_req else "Verified Depiction Record",
                        "verification_required": ver_req,
                        "investigative_status": "Depiction Record",
                        "case_id": case_id_str
                    }
                )
            else:
                is_device_rel = rel_type in ["STORED_ON_DEVICE", "EXTRACTED_FROM", "RECOVERED_FROM_DEVICE"]
                if not has_device or not is_device_rel:
                    person_rel = "ASSOCIATED_WITH" if (is_device_rel or rel_type == "BELONGS_TO_CASE") else rel_type
                    add_qualified_edge(
                        graph,
                        ev_id,
                        suspect_str,
                        {
                            "relationship": person_rel,
                            "relationship_type": person_rel,
                            "confidence": conf,
                            "source": "Case Database Link",
                            "status": "Candidate Association (Verification Required)" if ver_req else "Verified Association",
                            "verification_required": ver_req,
                            "investigative_status": "Candidate Association" if ver_req else "Verified Association",
                            "case_id": case_id_str
                        }
                    )

    # 4. Integrate CBIR visual similarity / duplicate relationships
    all_extra_rels = []
    if cbir_relationships and isinstance(cbir_relationships, list):
        all_extra_rels.extend(cbir_relationships)
    if duplicate_relationships and isinstance(duplicate_relationships, list):
        all_extra_rels.extend(duplicate_relationships)

    if all_extra_rels:
        for rel in all_extra_rels:
            if not isinstance(rel, dict):
                continue
            src = rel.get("source_evidence")
            tgt = rel.get("target_evidence")
            if not src or not tgt or src == tgt:
                continue

            src_str = str(src)
            tgt_str = str(tgt)

            # Check if relationship candidate is a person candidate from CBIR
            is_person_candidate = bool(
                rel.get("is_person_candidate")
                or rel.get("is_possible_suspect")
                or rel.get("candidate_type") in ["person", "suspect", "possible_suspect"]
                or rel.get("target_type") in ["person", "suspect", "possible_suspect", "Person", "Suspect", "Possible Suspect", "Person / Entity"]
                or rel.get("category") in ["persons", "person"]
            )

            # Ensure nodes exist
            if not graph.has_node(src_str):
                graph.add_node(src_str, type="Evidence", label=src_str)
            if not graph.has_node(tgt_str):
                if is_person_candidate:
                    candidate_details = MetadataAdapter.build_clean_node_details(
                        tgt_str,
                        {
                            "type": "Possible Suspect",
                            "label": tgt_str,
                            "case_id": case_id_str,
                            "source": "CBIR Visual Analysis",
                            "is_cbir_candidate": True,
                            "is_cbir_person": True
                        }
                    )
                    graph.add_node(
                        tgt_str,
                        type="Possible Suspect",
                        label=tgt_str,
                        entity_id=tgt_str,
                        is_cbir_candidate=True,
                        is_cbir_person=True,
                        source="CBIR Visual Analysis",
                        node_details=candidate_details
                    )
                else:
                    graph.add_node(tgt_str, type="Evidence", label=tgt_str)

            is_exact = bool(
                rel.get("sha256_exact_duplicate")
                or rel.get("is_exact_hash_match")
                or rel.get("relationship_type") == "EXACT_FILE_DUPLICATE"
                or rel.get("relationship") == "Exact Duplicate File"
            )
            cbir_rel_type = "EXACT_FILE_DUPLICATE" if is_exact else "CBIR_VISUAL_RELATIONSHIP"
            edge_source = "CBIR File Hash Match" if is_exact else "CBIR Visual Analysis"
            edge_status = "Exact Duplicate File" if is_exact else rel.get("investigation_status", "Candidate")
            edge_reason = (
                "SHA-256 hashes are identical; files are exact bit-for-bit duplicates."
                if is_exact
                else f"Visual resemblance candidate (score {rel.get('similarity', 0.0):.4f}). Verification required."
            )

            if is_exact:
                if graph.has_node(src_str) and "node_details" in graph.nodes[src_str]:
                    graph.nodes[src_str]["node_details"]["duplicate_status"] = "EXACT DUPLICATE — VERIFIED"
                if graph.has_node(tgt_str) and "node_details" in graph.nodes[tgt_str]:
                    graph.nodes[tgt_str]["node_details"]["duplicate_status"] = "EXACT DUPLICATE — VERIFIED"

            add_qualified_edge(
                graph,
                src_str,
                tgt_str,
                {
                    "relationship": rel.get("relationship", rel.get("classification", "Visual Comparison")),
                    "relationship_type": cbir_rel_type,
                    "confidence": float(rel.get("confidence", rel.get("similarity", 0.0))),
                    "similarity": float(rel.get("similarity", 0.0)),
                    "source": edge_source,
                    "status": edge_status,
                    "verification_required": not is_exact,
                    "investigative_status": "Exact Duplicate" if is_exact else rel.get("investigation_status", "Candidate"),
                    "reason": edge_reason,
                    "case_id": case_id_str
                }
            )

    return graph


def is_cbir_person_candidate(node_id, data, graph=None):
    """
    Determine whether a graph node represents a person candidate obtained
    through CBIR visual similarity.
    Forensic safety: CBIR-created person-related nodes must be displayed as
    'Possible Suspect', NEVER as a confirmed suspect or confirmed person.
    Strictly preserves confirmed/registered persons from trusted case database records.
    """
    if not data:
        return False
    if data.get("is_cbir_candidate") or data.get("is_cbir_person") or data.get("is_possible_suspect"):
        return True

    raw_type = str(data.get("type", "")).strip()
    if raw_type.lower() == "possible suspect":
        return True

    src = str(data.get("source", "")).lower()
    src_type = str(data.get("source_type", "")).lower()

    # Generic internal types like PERSON, ENTITY, Person / Entity derived from CBIR
    if raw_type.upper() in ["PERSON", "ENTITY", "PERSON / ENTITY", "PERSON/ENTITY", "CANDIDATE"]:
        if "cbir" in src or "cbir" in src_type:
            return True
        if graph and graph.has_node(node_id):
            edge_sources = [
                str(graph.get_edge_data(node_id, n, {}).get("source", "")).lower()
                for n in graph.neighbors(node_id)
            ]
            has_cbir_edge = any("cbir" in s for s in edge_sources)
            has_db_edge = any("database" in s or "case registry" in s for s in edge_sources)
            if has_cbir_edge and not has_db_edge:
                return True

    return False


def serialize_graph(graph, case_id=None):
    """
    Serialize a NetworkX graph into clean machine-readable dictionaries
    for JSON reporting and frontend APIs.
    """
    nodes = []
    edges = []

    for node_id, data in graph.nodes(data=True):
        img_p = data.get("image_path")
        fn = os.path.basename(img_p) if img_p else data.get("filename")
        raw_type = data.get("type", "Entity")

        is_cbir_person = is_cbir_person_candidate(node_id, data, graph)

        if is_cbir_person:
            display_type = "Possible Suspect"
            type_badge = "Possible Suspect"
            badge = "Possible Suspect"
            tooltip = f"Possible Suspect: Visual resemblance candidate from CBIR for {data.get('label', node_id)}. Verification required; does not confirm identity."
        elif raw_type.lower() in ["case", "case root"]:
            display_type = "Case"
            type_badge = "Case"
            badge = "Case"
            tooltip = f"Case: {data.get('label', node_id)}"
        elif "device" in raw_type.lower():
            display_type = "Device"
            type_badge = raw_type
            badge = "Device"
            tooltip = f"Device: {data.get('label', node_id)}"
        elif "person" in raw_type.lower() or "suspect" in raw_type.lower():
            # Trusted case data (Registered in database link)
            display_type = "Person / Suspect"
            type_badge = "Person / Suspect"
            badge = "Person / Suspect"
            tooltip = f"Person / Suspect: {data.get('label', node_id)} (Registered in case data)"
        else:
            display_type = "Evidence (File)" if raw_type == "Evidence" else raw_type
            type_badge = "Evidence (File)" if raw_type == "Evidence" else raw_type
            badge = "Evidence"
            tooltip = f"{raw_type}: {data.get('label', node_id)}"

        node_entry = {
            "id": str(node_id),
            "evidence_id": str(node_id),
            "label": data.get("label", str(node_id)),
            "name": data.get("label", str(node_id)),
            "type": "Possible Suspect" if is_cbir_person else raw_type,
            "display_type": display_type,
            "type_badge": type_badge,
            "badge": badge,
            "tooltip": tooltip,
            "is_possible_suspect": is_cbir_person,
            "evidence_type": "Possible Suspect" if is_cbir_person else raw_type,
            "category": data.get("category"),
            "image_path": img_p,
            "filename": fn,
            "source": data.get("source", "Case Registry"),
            "status": data.get("status", "Active"),
            "case_id": str(case_id) if case_id else None,
            "metadata": data.get("metadata", {}),
            "node_details": data.get("node_details", {})
        }

        # If node_details is present, ensure its terminology matches
        if is_cbir_person and "node_details" in node_entry and node_entry["node_details"]:
            node_entry["node_details"] = dict(node_entry["node_details"])
            node_entry["node_details"]["entity_category"] = "Possible Suspect"
            node_entry["node_details"]["display_type"] = "Possible Suspect"
            node_entry["node_details"]["type_badge"] = "Possible Suspect"
            node_entry["node_details"]["badge"] = "Possible Suspect"
            node_entry["node_details"]["role"] = "Possible Suspect"
            node_entry["node_details"]["verification_required"] = True

        nodes.append(node_entry)

    seen_edge_identities = set()
    for u, v, data in graph.edges(data=True):
        all_rels = data.get("parallel_relationships", [data])
        for rel_dict in all_rels:
            rel_type = rel_dict.get("relationship_type", rel_dict.get("relationship", "ASSOCIATION"))
            stable_key = tuple(sorted([str(u), str(v)])) + (rel_type,)
            if stable_key in seen_edge_identities:
                continue
            seen_edge_identities.add(stable_key)

            rel_disp = rel_dict.get("relationship", "ASSOCIATED_WITH")
            conf_val = float(rel_dict.get("confidence", 1.0))
            edges.append({
                "source_id": str(u),
                "target_id": str(v),
                "source": str(u),
                "target": str(v),
                "relationship": rel_disp,
                "relationship_type": rel_type,
                "confidence": conf_val,
                "similarity": rel_dict.get("similarity"),
                "source_type": rel_dict.get("source", "Case Database Link"),
                "source": rel_dict.get("source", "Case Database Link"),
                "status": rel_dict.get("status", "Candidate"),
                "verification_required": bool(rel_dict.get("verification_required", True)),
                "investigation_status": rel_dict.get("investigative_status", "Candidate"),
                "reason": rel_dict.get("reason", f"Relationship {rel_type} between {u} and {v}"),
                "case_id": rel_dict.get("case_id", str(case_id) if case_id else ""),
                "tooltip": f"{rel_disp} (Confidence: {conf_val:.2f})"
            })

    # Standard Graph Legend: Case, Evidence (File), Possible Suspect, Device
    legend = [
        {"label": "Case", "type": "Case", "color": "#FFD700"},
        {"label": "Evidence (File)", "type": "Evidence", "color": "#87CEEB"},
        {"label": "Possible Suspect", "type": "Possible Suspect", "color": "#FF7F7F", "description": "Candidate associated via CBIR visual similarity (verification required)"},
        {"label": "Device", "type": "Device", "color": "#DDA0DD"},
    ]
    # If trusted confirmed/registered persons exist in this case, include Person / Suspect in legend
    has_trusted_person = any(
        ("person" in str(n.get("type", "")).lower() or "suspect" in str(n.get("type", "")).lower())
        and not n.get("is_possible_suspect")
        for n in nodes
    )
    if has_trusted_person:
        legend.append({
            "label": "Person / Suspect",
            "type": "Person / Suspect",
            "color": "#FF7F7F",
            "description": "Confirmed/registered person or suspect entity from case records"
        })

    filter_categories = [item["label"] for item in legend]

    return {
        "nodes": nodes,
        "edges": edges,
        "total_nodes": len(nodes),
        "total_edges": len(edges),
        "case_id": str(case_id) if case_id else None,
        "legend": legend,
        "filter_categories": filter_categories
    }


def get_node_details(case_id, node_id):
    """
    Retrieve clean investigator-facing Node Details for a specific entity in a case.
    Strictly excludes raw SHA-256 digests and internal filesystem paths.
    """
    if not case_id or not node_id:
        return {"error": "case_id and node_id are required"}

    graph = build_case_relationship_graph(case_id)
    nid = str(node_id).strip()
    if not graph.has_node(nid):
        return {"status": "not_found", "message": f"Node '{nid}' not found in case '{case_id}'"}

    data = graph.nodes[nid]
    is_cbir = is_cbir_person_candidate(nid, data, graph)

    if "node_details" in data and data["node_details"]:
        details = dict(data["node_details"])
        if is_cbir:
            details["entity_category"] = "Possible Suspect"
            details["display_type"] = "Possible Suspect"
            details["type_badge"] = "Possible Suspect"
            details["badge"] = "Possible Suspect"
            details["role"] = "Possible Suspect"
            details["status"] = "Candidate Only (Verification Required)"
            details["verification_required"] = True
            details["investigative_status"] = "Candidate Only — Verification Required"
            details["forensic_notice"] = (
                "CBIR visual similarity candidate only. Does NOT establish confirmed identity. "
                "Verification required by authorized investigator."
            )
        return details

    details = MetadataAdapter.build_clean_node_details(nid, data)
    if is_cbir:
        details["entity_category"] = "Possible Suspect"
        details["display_type"] = "Possible Suspect"
        details["type_badge"] = "Possible Suspect"
        details["badge"] = "Possible Suspect"
        details["role"] = "Possible Suspect"
        details["verification_required"] = True
    return details


def find_relationship_path(case_id, source_id, target_id):
    """
    Find and explain the shortest forensic relationship path between two entities in the same case.

    Parameters
    ----------
    case_id : str
        Mandatory case identifier.
    source_id : str
        Source entity or evidence identifier.
    target_id : str
        Target entity or evidence identifier.

    Returns
    -------
    dict
        Status, relationship path string, step-by-step explanation, or safe 'no_relationship_found'.
    """
    if not case_id:
        return {
            "status": "error",
            "message": "case_id is mandatory.",
            "case_id": None,
            "source_id": str(source_id) if source_id else None,
            "target_id": str(target_id) if target_id else None,
            "relationship_path": None,
            "path": []
        }

    graph = build_case_relationship_graph(case_id)
    src = str(source_id).strip()
    tgt = str(target_id).strip()
    case_id_str = str(case_id).strip()

    if not graph.has_node(src) or not graph.has_node(tgt):
        return {
            "status": "no_relationship_found",
            "message": f"No supported relationship path was found between the selected entities in {case_id_str}.",
            "case_id": case_id_str,
            "source_id": src,
            "target_id": tgt,
            "relationship_path": None,
            "path": []
        }

    # Trace through actual forensic relationships (device, person, extracted, stored, duplicate, CBIR),
    # excluding trivial case-root traversal unless the case node itself is being queried.
    subgraph = graph.copy()
    if src != case_id_str and tgt != case_id_str and subgraph.has_node(case_id_str):
        subgraph.remove_node(case_id_str)

    if not nx.has_path(subgraph, src, tgt):
        return {
            "status": "no_relationship_found",
            "message": f"No supported relationship path was found between the selected entities in {case_id_str}.",
            "case_id": case_id_str,
            "source_id": src,
            "target_id": tgt,
            "relationship_path": None,
            "path": []
        }

    node_path = nx.shortest_path(subgraph, src, tgt)
    segments = []
    text_steps = []

    for i in range(len(node_path) - 1):
        u = node_path[i]
        v = node_path[i + 1]
        edge_data = subgraph.get_edge_data(u, v) or {}
        rel_type = edge_data.get("relationship_type", edge_data.get("relationship", "ASSOCIATED_WITH"))
        src_label = subgraph.nodes[u].get("label", u)
        tgt_label = subgraph.nodes[v].get("label", v)
        segments.append({
            "from_id": u,
            "from_label": src_label,
            "to_id": v,
            "to_label": tgt_label,
            "relationship_type": rel_type,
            "confidence": float(edge_data.get("confidence", 1.0)),
            "verification_required": bool(edge_data.get("verification_required", True))
        })
        if i == 0:
            text_steps.append(f"{src_label} -> {rel_type} -> {tgt_label}")
        else:
            text_steps.append(f"{rel_type} -> {tgt_label}")

    full_rel_path = " -> ".join(text_steps)
    node_labels_path = " -> ".join([subgraph.nodes[n].get("label", n) for n in node_path])

    return {
        "status": "success",
        "case_id": case_id_str,
        "source_id": src,
        "target_id": tgt,
        "path_length": len(node_path) - 1,
        "nodes": node_path,
        "segments": segments,
        "relationship_path": full_rel_path,
        "node_path": node_labels_path,
        "explanation": full_rel_path,
        "reason": f"Found direct relationship path ({len(node_path) - 1} hops) between '{src}' and '{tgt}' in {case_id_str}: {full_rel_path}"
    }


if __name__ == "__main__":
    print("=" * 60)
    print("DIGITAL EVIDENCE EPRA - CASE GRAPH ENGINE TEST")
    print("=" * 60)

    g = build_case_relationship_graph("CASE_TEST_01")
    serialized = serialize_graph(g)

    print(f"\nCase: CASE_TEST_01")
    print(f"Total Nodes : {serialized['total_nodes']}")
    print(f"Total Edges : {serialized['total_edges']}")

    print("\nNODES:")
    for n in serialized["nodes"]:
        print(f"  [{n['type']}] {n['id']}")

    print("\nEDGES:")
    for e in serialized["edges"]:
        print(f"  {e['source']} --({e['relationship']})--> {e['target']} [Conf: {e['confidence']}]")
