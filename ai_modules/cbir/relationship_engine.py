# ============================================================
# Digital Evidence EPRA
#
# Module : CBIR
# File   : relationship_engine.py
# Purpose: Generate investigation-safe evidence relationships
#          from CBIR visual comparison results
#
# Author : Member 3 (Trisha)
# ============================================================

from duplicate_detector import detect_duplicate


# ============================================================
# GENERATE EVIDENCE RELATIONSHIPS
# ============================================================

def generate_relationships(
    source_evidence,
    search_results
):
    """
    Generate investigation-safe relationships between
    source evidence and CBIR candidate evidence.

    IMPORTANT:
    These relationships represent VISUAL CBIR relationships.
    They do NOT establish:
        - same person
        - same object
        - same device
        - same location
        - same crime
        - same source
        - authenticity

    Final forensic interpretation must be performed
    by an authorized investigator.
    """

    relationships = []

    if not source_evidence:
        return relationships

    if not isinstance(search_results, list):
        return relationships

    for result in search_results:

        if not isinstance(result, dict):
            continue

        # ----------------------------------------------------
        # Evidence identification
        # ----------------------------------------------------

        target_evidence = result.get(
            "evidence_id"
        )

        if not target_evidence:
            continue

        target_evidence = str(
            target_evidence
        )

        source_evidence = str(
            source_evidence
        )

        # ----------------------------------------------------
        # Never relate evidence to itself
        # ----------------------------------------------------

        if target_evidence == source_evidence:
            continue

        # ----------------------------------------------------
        # Read similarity safely
        # ----------------------------------------------------

        try:
            similarity = float(
                result.get(
                    "similarity",
                    0.0
                )
            )
        except (TypeError, ValueError):
            continue

        similarity = max(
            0.0,
            min(
                1.0,
                similarity
            )
        )

        # ----------------------------------------------------
        # CBIR classification
        # ----------------------------------------------------

        duplicate_result = detect_duplicate(
            similarity
        )

        # ----------------------------------------------------
        # Preserve available evidence metadata
        # ----------------------------------------------------

        category = result.get(
            "category"
        )

        image_path = result.get(
            "image",
            result.get(
                "image_path"
            )
        )

        semantic = result.get(
            "semantic_score"
        )

        if semantic is None:
            semantic = similarity

        try:
            semantic = float(
                semantic
            )
        except (TypeError, ValueError):
            semantic = similarity

        semantic = max(
            0.0,
            min(
                1.0,
                semantic
            )
        )

        # ----------------------------------------------------
        # Investigation-safe relationship
        # ----------------------------------------------------

        relationship = duplicate_result.get(
            "classification",
            "Visual Comparison Candidate"
        )

        investigative_status = duplicate_result.get(
            "investigative_status",
            "Requires Investigator Review"
        )

        action = duplicate_result.get(
            "action",
            "Manual Verification Required"
        )

        confidence_level = duplicate_result.get(
            "confidence_level",
            "Unknown"
        )

        visual_resemblance = duplicate_result.get(
            "visual_resemblance",
            False
        )

        # ----------------------------------------------------
        # Graph-ready relationship record
        # ----------------------------------------------------

        relationship_record = {

            # Evidence nodes
            "source_evidence":
                source_evidence,

            "target_evidence":
                target_evidence,

            # Relationship information
            "relationship":
                relationship,

            "relationship_type":
                "CBIR_VISUAL_RELATIONSHIP",

            # Numerical CBIR information
            "similarity":
                float(
                    round(
                        similarity,
                        4
                    )
                ),

            "semantic_score":
                float(
                    round(
                        semantic,
                        2
                    )
                ),

            # Interpretation
            "confidence_level":
                confidence_level,

            "visual_resemblance":
                bool(
                    visual_resemblance
                ),

            "investigative_status":
                investigative_status,

            "action":
                action,

            # Evidence metadata
            "category":
                category,

            "image":
                image_path,

            # Important forensic limitation
            "forensic_claim":
                "Visual similarity only; "
                "does not establish identity or "
                "common source."
        }

        relationships.append(
            relationship_record
        )

    return relationships


# ============================================================
# FILTER GRAPH RELATIONSHIPS
# ============================================================

def get_graph_relationships(
    relationships
):
    """
    Return relationships suitable for displaying
    as investigation graph connections.

    Weak/no-significant visual matches are excluded.

    IMPORTANT:
    Exclusion does NOT mean the evidence is unrelated
    in the forensic sense. It only means CBIR did not
    identify sufficient visual resemblance.
    """

    graph_relationships = []

    if not isinstance(
        relationships,
        list
    ):
        return graph_relationships

    for relationship in relationships:

        if not isinstance(
            relationship,
            dict
        ):
            continue

        status = relationship.get(
            "investigative_status",
            ""
        )

        rel_type = relationship.get("relationship", "")
        if (
            status in (
                "Duplicate Candidate",
                "Near-Duplicate Candidate",
                "Strong Visual Candidate",
                "Possible Visual Candidate",
                "Candidate",
                "Possible Relationship"
            )
            or rel_type in (
                "Exact Duplicate",
                "Near Duplicate",
                "Very Strong Visual Match",
                "Strong Visual Match",
                "Possible Visual Resemblance"
            )
            or (relationship.get("visual_resemblance") and relationship.get("similarity", 0.0) >= 0.60)
        ):
            graph_relationships.append(
                relationship
            )

    return graph_relationships


# ============================================================
# CREATE GRAPH NODE INFORMATION
# ============================================================

def create_graph_nodes(
    relationships
):
    """
    Extract unique evidence nodes from relationship records.

    Each node contains only evidence identification information.
    """

    nodes = []
    seen = set()

    if not isinstance(
        relationships,
        list
    ):
        return nodes

    for relationship in relationships:

        if not isinstance(
            relationship,
            dict
        ):
            continue

        source = relationship.get(
            "source_evidence"
        )

        target = relationship.get(
            "target_evidence"
        )

        category = relationship.get(
            "category"
        )

        image = relationship.get(
            "image"
        )

        for evidence_id in (
            source,
            target
        ):

            if not evidence_id:
                continue

            evidence_id = str(
                evidence_id
            )

            if evidence_id in seen:
                continue

            seen.add(
                evidence_id
            )

            nodes.append({

                "evidence_id":
                    evidence_id,

                "category":
                    category,

                "image":
                    image
            })

    return nodes


# ============================================================
# CREATE GRAPH EDGES
# ============================================================

def create_graph_edges(
    relationships
):
    """
    Convert relationship records into graph edges.

    This format can be consumed by the backend/frontend
    relationship graph.

    Edge labels represent CBIR visual relationships only.
    """

    edges = []

    if not isinstance(
        relationships,
        list
    ):
        return edges

    for relationship in relationships:

        if not isinstance(
            relationship,
            dict
        ):
            continue

        source = relationship.get(
            "source_evidence"
        )

        target = relationship.get(
            "target_evidence"
        )

        if not source or not target:
            continue

        edges.append({

            "source":
                str(source),

            "target":
                str(target),

            "label":
                relationship.get(
                    "relationship",
                    "Visual Comparison"
                ),

            "relationship_type":
                "CBIR_VISUAL_RELATIONSHIP",

            "similarity":
                relationship.get(
                    "similarity",
                    0.0
                ),

            "confidence":
                relationship.get(
                    "confidence_level",
                    "Unknown"
                ),

            "investigative_status":
                relationship.get(
                    "investigative_status",
                    "Requires Investigator Review"
                )
        })

    return edges


# ============================================================
# TESTING
# ============================================================

if __name__ == "__main__":

    print("=" * 75)
    print("DIGITAL EVIDENCE EPRA")
    print("CBIR RELATIONSHIP ENGINE TEST")
    print("=" * 75)

    sample_results = [

        {
            "evidence_id":
                "EV_PERSON2",

            "category":
                "persons",

            "image":
                "datasets/images/persons/person2.jpg",

            "similarity":
                0.97,

            "semantic_score":
                0.97
        },

        {
            "evidence_id":
                "EV_PERSON3",

            "category":
                "persons",

            "image":
                "datasets/images/persons/person3.jpg",

            "similarity":
                0.87,

            "semantic_score":
                0.87
        },

        {
            "evidence_id":
                "EV_PERSON4",

            "category":
                "persons",

            "image":
                "datasets/images/persons/person4.jpg",

            "similarity":
                0.78,

            "semantic_score":
                0.78
        },

        {
            "evidence_id":
                "EV_PERSON5",

            "category":
                "persons",

            "image":
                "datasets/images/persons/person5.jpg",

            "similarity":
                0.45,

            "semantic_score":
                0.45
        }
    ]

    # --------------------------------------------------------
    # Generate relationships
    # --------------------------------------------------------

    relationships = generate_relationships(
        source_evidence="EV_PERSON1",
        search_results=sample_results
    )

    print()
    print("CBIR RELATIONSHIPS")
    print("-" * 75)

    for relationship in relationships:

        print()

        print(
            f"Source Evidence      : "
            f"{relationship['source_evidence']}"
        )

        print(
            f"Target Evidence      : "
            f"{relationship['target_evidence']}"
        )

        print(
            f"Relationship         : "
            f"{relationship['relationship']}"
        )

        print(
            f"Relationship Type    : "
            f"{relationship['relationship_type']}"
        )

        print(
            f"Similarity           : "
            f"{relationship['similarity']:.4f}"
        )

        print(
            f"Semantic Score       : "
            f"{relationship['semantic_score']:.2f}"
        )

        print(
            f"Visual Resemblance   : "
            f"{relationship['visual_resemblance']}"
        )

        print(
            f"Confidence Level     : "
            f"{relationship['confidence_level']}"
        )

        print(
            f"Investigation Status : "
            f"{relationship['investigative_status']}"
        )

        print(
            f"Recommended Action   : "
            f"{relationship['action']}"
        )

        print(
            f"Category             : "
            f"{relationship['category']}"
        )

        print(
            f"Image                : "
            f"{relationship['image']}"
        )

        print(
            f"Forensic Limitation : "
            f"{relationship['forensic_claim']}"
        )

        print("-" * 75)

    # --------------------------------------------------------
    # Graph relationships
    # --------------------------------------------------------

    graph_relationships = get_graph_relationships(
        relationships
    )

    print()
    print("GRAPH RELATIONSHIPS")
    print("-" * 75)

    for relationship in graph_relationships:

        print(
            f"{relationship['source_evidence']} "
            f"--> "
            f"{relationship['target_evidence']} "
            f"| "
            f"{relationship['relationship']} "
            f"| "
            f"{relationship['similarity']:.2f}"
        )

    # --------------------------------------------------------
    # Graph nodes
    # --------------------------------------------------------

    nodes = create_graph_nodes(
        relationships
    )

    print()
    print("GRAPH NODES")
    print("-" * 75)

    for node in nodes:
        print(
            f"Evidence ID : "
            f"{node['evidence_id']}"
        )

    # --------------------------------------------------------
    # Graph edges
    # --------------------------------------------------------

    edges = create_graph_edges(
        graph_relationships
    )

    print()
    print("GRAPH EDGES")
    print("-" * 75)

    for edge in edges:

        print(
            f"{edge['source']} "
            f"--> "
            f"{edge['target']} "
            f"| Label: "
            f"{edge['label']} "
            f"| Similarity: "
            f"{edge['similarity']:.2f}"
        )

    print()
    print("=" * 75)
    print("RELATIONSHIP ENGINE TEST COMPLETED")
    print("=" * 75)

    print()
    print("IMPORTANT:")
    print(
        "CBIR relationships represent visual comparison "
        "results only."
    )
    print(
        "They must not be interpreted as proof of identity, "
        "common source, or criminal association."
    )
    print("=" * 75)