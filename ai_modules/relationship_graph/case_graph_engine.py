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


def build_case_relationship_graph(case_id, cbir_relationships=None):
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
        graph.add_edge(
            ev_id,
            case_id_str,
            relationship="BELONGS_TO_CASE",
            relationship_type="BELONGS_TO_CASE",
            confidence=1.0,
            source="Case Registry",
            status="Confirmed Case Evidence",
            verification_required=False,
            investigative_status="Confirmed Case Evidence",
            case_id=case_id_str
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
            graph.add_edge(
                ev_id,
                case_id_str,
                relationship="BELONGS_TO_CASE",
                relationship_type="BELONGS_TO_CASE",
                confidence=1.0,
                source="Case Registry",
                status="Confirmed Case Evidence",
                verification_required=False,
                investigative_status="Confirmed Case Evidence",
                case_id=case_id_str
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
            graph.add_edge(
                ev_id,
                device_str,
                relationship=dev_rel_type,
                relationship_type=dev_rel_type,
                confidence=conf,
                source="Case Database Link",
                status="Candidate Hardware Link" if ver_req else "Verified Hardware Link",
                verification_required=ver_req,
                investigative_status="Candidate Hardware Link" if ver_req else "Verified Hardware Link",
                case_id=case_id_str
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
                graph.add_edge(
                    device_str,
                    suspect_str,
                    relationship="OWNED_OR_USED_BY",
                    relationship_type="OWNED_OR_USED_BY",
                    confidence=conf,
                    source="Case Database Link",
                    status="Candidate Device User (Verification Required)",
                    verification_required=True,
                    investigative_status="Candidate Device User",
                    case_id=case_id_str
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
                graph.add_edge(
                    ev_id,
                    suspect_str,
                    relationship="DEPICTS_PERSON",
                    relationship_type="DEPICTS_PERSON",
                    confidence=conf,
                    source="Case Database Link",
                    status="Depiction Record (Verification Required)" if ver_req else "Verified Depiction Record",
                    verification_required=ver_req,
                    investigative_status="Depiction Record",
                    case_id=case_id_str
                )
            else:
                is_device_rel = rel_type in ["STORED_ON_DEVICE", "EXTRACTED_FROM", "RECOVERED_FROM_DEVICE"]
                if not has_device or not is_device_rel:
                    person_rel = "ASSOCIATED_WITH" if is_device_rel else rel_type
                    graph.add_edge(
                        ev_id,
                        suspect_str,
                        relationship=person_rel,
                        relationship_type=person_rel,
                        confidence=conf,
                        source="Case Database Link",
                        status="Candidate Association (Verification Required)" if ver_req else "Verified Association",
                        verification_required=ver_req,
                        investigative_status="Candidate Association" if ver_req else "Verified Association",
                        case_id=case_id_str
                    )

    # 4. Integrate CBIR visual similarity / duplicate relationships
    if cbir_relationships and isinstance(cbir_relationships, list):
        for rel in cbir_relationships:
            if not isinstance(rel, dict):
                continue
            src = rel.get("source_evidence")
            tgt = rel.get("target_evidence")
            if not src or not tgt or src == tgt:
                continue

            src_str = str(src)
            tgt_str = str(tgt)

            # Ensure nodes exist
            if not graph.has_node(src_str):
                graph.add_node(src_str, type="Evidence", label=src_str)
            if not graph.has_node(tgt_str):
                graph.add_node(tgt_str, type="Evidence", label=tgt_str)

            is_exact = bool(rel.get("sha256_exact_duplicate") or rel.get("is_exact_hash_match"))
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

            graph.add_edge(
                src_str,
                tgt_str,
                relationship=rel.get("relationship", rel.get("classification", "Visual Comparison")),
                relationship_type=cbir_rel_type,
                confidence=float(rel.get("confidence", rel.get("similarity", 0.0))),
                similarity=float(rel.get("similarity", 0.0)),
                source=edge_source,
                status=edge_status,
                verification_required=not is_exact,
                investigative_status="Exact Duplicate" if is_exact else rel.get("investigation_status", "Candidate"),
                reason=edge_reason,
                case_id=case_id_str
            )

    return graph


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
        nodes.append({
            "id": str(node_id),
            "evidence_id": str(node_id),
            "label": data.get("label", str(node_id)),
            "name": data.get("label", str(node_id)),
            "type": data.get("type", "Entity"),
            "evidence_type": data.get("type", "Entity"),
            "category": data.get("category"),
            "image_path": img_p,
            "filename": fn,
            "source": data.get("source", "Case Registry"),
            "status": data.get("status", "Active"),
            "case_id": str(case_id) if case_id else None,
            "metadata": data.get("metadata", {}),
            "node_details": data.get("node_details", {})
        })

    for u, v, data in graph.edges(data=True):
        edges.append({
            "source_id": str(u),
            "target_id": str(v),
            "source": str(u),
            "target": str(v),
            "relationship": data.get("relationship", "ASSOCIATED_WITH"),
            "relationship_type": data.get("relationship_type", "ASSOCIATION"),
            "confidence": float(data.get("confidence", 1.0)),
            "similarity": data.get("similarity"),
            "source_type": data.get("source", "Case Database Link"),
            "source": data.get("source", "Case Database Link"),
            "status": data.get("status", "Candidate"),
            "verification_required": bool(data.get("verification_required", True)),
            "investigation_status": data.get("investigative_status", "Candidate"),
            "reason": data.get("reason", f"Relationship {data.get('relationship_type')} between {u} and {v}"),
            "case_id": data.get("case_id", str(case_id) if case_id else "")
        })

    return {
        "nodes": nodes,
        "edges": edges,
        "total_nodes": len(nodes),
        "total_edges": len(edges),
        "case_id": str(case_id) if case_id else None
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
    if "node_details" in data and data["node_details"]:
        return data["node_details"]

    return MetadataAdapter.build_clean_node_details(nid, data)


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
