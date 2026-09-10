# ============================================================
# Digital Evidence EPRA
#
# Module : CBIR
# File   : cbir_service.py
# Purpose: Main CBIR investigation pipeline
#
# Author : Member 3 (Trisha)
# ============================================================

from feature_database import get_case_evidence

from image_search import (
    search_similar_images,
    format_search_results
)

from duplicate_detector import (
    process_duplicate_results
)

from relationship_engine import (
    generate_relationships,
    get_graph_relationships,
    create_graph_nodes,
    create_graph_edges
)


# ============================================================
# MAIN CBIR PIPELINE
# ============================================================

def run_cbir(
    case_id,
    evidence_id,
    top_k=5
):
    """
    Execute the complete CBIR pipeline for one evidence item.

    Pipeline:

        Case
          ↓
        Evidence validation
          ↓
        Query image
          ↓
        Case-restricted CBIR search
          ↓
        Visual similarity
          ↓
        Conservative classification
          ↓
        Evidence relationships
          ↓
        Graph-ready nodes and edges

    IMPORTANT:
    CBIR provides visual comparison assistance only.

    It does NOT establish:
        - same person
        - same object
        - same device
        - same source
        - same location
        - same crime
        - authenticity
    """

    # --------------------------------------------------------
    # Validate case ID
    # --------------------------------------------------------

    if not case_id:

        return {
            "status": "Error",
            "message": "Case ID was not provided.",
            "case_id": None,
            "source_evidence": None,
            "matches": [],
            "relationships": [],
            "graph": {
                "nodes": [],
                "edges": []
            }
        }

    # --------------------------------------------------------
    # Validate evidence ID
    # --------------------------------------------------------

    if not evidence_id:

        return {
            "status": "Error",
            "message": "Evidence ID was not provided.",
            "case_id": str(case_id),
            "source_evidence": None,
            "matches": [],
            "relationships": [],
            "graph": {
                "nodes": [],
                "edges": []
            }
        }

    case_id = str(case_id)
    evidence_id = str(evidence_id)

    # --------------------------------------------------------
    # Validate top_k
    # --------------------------------------------------------

    try:
        top_k = int(top_k)
    except (TypeError, ValueError):
        top_k = 5

    top_k = max(
        1,
        min(
            top_k,
            50
        )
    )

    # --------------------------------------------------------
    # Fetch evidence belonging ONLY to selected case
    # --------------------------------------------------------

    case_evidence = get_case_evidence(
        case_id
    )

    if not case_evidence:

        return {
            "status": "No Evidence",
            "message":
                "No evidence was found for the selected case.",
            "case_id": case_id,
            "source_evidence": evidence_id,
            "matches": [],
            "relationships": [],
            "graph": {
                "nodes": [],
                "edges": []
            }
        }

    # --------------------------------------------------------
    # Find selected evidence
    # --------------------------------------------------------

    query_evidence = None

    for evidence in case_evidence:

        if not isinstance(
            evidence,
            dict
        ):
            continue

        current_id = evidence.get(
            "evidence_id"
        )

        if current_id is None:
            continue

        if str(current_id) == evidence_id:

            query_evidence = evidence
            break

    # --------------------------------------------------------
    # Verify evidence belongs to selected case
    # --------------------------------------------------------

    if query_evidence is None:

        return {
            "status": "Error",
            "message":
                "Selected evidence does not belong to "
                "the selected case.",
            "case_id": case_id,
            "source_evidence": evidence_id,
            "matches": [],
            "relationships": [],
            "graph": {
                "nodes": [],
                "edges": []
            }
        }

    # --------------------------------------------------------
    # Get query image path
    # --------------------------------------------------------

    query_image_path = query_evidence.get(
        "image_path"
    )

    if not query_image_path:

        return {
            "status": "Error",
            "message":
                "Selected evidence does not contain "
                "a valid image path.",
            "case_id": case_id,
            "source_evidence": evidence_id,
            "matches": [],
            "relationships": [],
            "graph": {
                "nodes": [],
                "edges": []
            }
        }

    # --------------------------------------------------------
    # Search ONLY inside selected case
    # --------------------------------------------------------

    raw_matches = search_similar_images(

        query_image_path=query_image_path,

        case_evidence=case_evidence,

        top_k=top_k
    )

    # --------------------------------------------------------
    # Format CBIR results
    # --------------------------------------------------------

    formatted_matches = format_search_results(
        raw_matches
    )

    # --------------------------------------------------------
    # Apply conservative classification
    # --------------------------------------------------------

    final_matches = process_duplicate_results(
        formatted_matches
    )

    # --------------------------------------------------------
    # Add explicit source evidence information
    # --------------------------------------------------------

    for match in final_matches:

        match["source_evidence_id"] = evidence_id

        match["query_image"] = query_image_path

        match["case_id"] = case_id

        match["comparison_type"] = (
            "CBIR visual comparison"
        )

    # --------------------------------------------------------
    # Generate evidence relationships
    # --------------------------------------------------------

    relationships = generate_relationships(

        source_evidence=evidence_id,

        search_results=final_matches
    )

    # --------------------------------------------------------
    # Keep only relationships suitable for graph
    # --------------------------------------------------------

    graph_relationships = get_graph_relationships(
        relationships
    )

    # --------------------------------------------------------
    # Generate graph nodes
    # --------------------------------------------------------

    graph_nodes = create_graph_nodes(
        graph_relationships
    )

    # --------------------------------------------------------
    # Generate graph edges
    # --------------------------------------------------------

    graph_edges = create_graph_edges(
        graph_relationships
    )

    # --------------------------------------------------------
    # Final response
    # --------------------------------------------------------

    return {

        "status":
            "Success",

        "case_id":
            case_id,

        "source_evidence":
            evidence_id,

        "query_image":
            query_image_path,

        "comparison_scope":
            "Selected case evidence only",

        "total_case_evidence":
            len(case_evidence),

        "results_returned":
            len(final_matches),

        "matches":
            final_matches,

        "relationships":
            relationships,

        "graph":
            {
                "nodes":
                    graph_nodes,

                "edges":
                    graph_edges
            },

        "forensic_notice":
            "CBIR results represent visual comparison "
            "assistance only. Similarity does not establish "
            "identity, common source, authenticity, or "
            "criminal association. Investigator verification "
            "is required."
    }


# ============================================================
# BACKEND WRAPPER
# ============================================================

def process_case(
    case_id,
    evidence_id,
    top_k=5
):
    """
    Backend integration entry point.

    The backend can call this function when an investigator
    requests CBIR analysis for a selected evidence item.
    """

    return run_cbir(
        case_id=case_id,
        evidence_id=evidence_id,
        top_k=top_k
    )


# ============================================================
# SIMPLE PIPELINE TEST
# ============================================================

if __name__ == "__main__":

    print("=" * 75)
    print("DIGITAL EVIDENCE EPRA")
    print("CBIR COMPLETE PIPELINE")
    print("=" * 75)

    print()

    print(
        "CBIR service is ready."
    )

    print()

    print(
        "Backend input required:"
    )

    print(
        "1. case_id"
    )

    print(
        "2. evidence_id"
    )

    print(
        "3. optional top_k"
    )

    print()

    print(
        "Pipeline:"
    )

    print(
        "Case -> Evidence -> Image Search -> "
        "Similarity -> Classification -> "
        "Relationships -> Graph"
    )

    print()

    print(
        "Search scope:"
    )

    print(
        "Selected case evidence ONLY"
    )

    print()

    print(
        "No case IDs, evidence IDs or image paths "
        "are hardcoded."
    )

    print()

    print("=" * 75)