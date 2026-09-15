import os
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import networkx as nx
from graph_builder import build_graph


COLOR_MAP = {
    "Case": "#FFD700",                     # Gold
    "Possible Suspect": "#FF7F7F",         # Light Coral (CBIR visual similarity candidate)
    "Person / Suspect": "#FF7F7F",         # Light Coral (Trusted case database record)
    "Suspect": "#FF7F7F",                  # Light Coral
    "Device": "#DDA0DD",                   # Plum
    "Device: Mobile Phone": "#BA55D3",     # Medium Orchid
    "Device: Computer": "#9370DB",         # Medium Purple
    "Evidence: Document": "#FFA500",       # Orange
    "Evidence: Person Photo": "#87CEFA",   # Light Sky Blue
    "Evidence: Crime Scene": "#90EE90",    # Light Green
    "Evidence: Weapon": "#F08080",         # Light Coral
    "Evidence: Vehicle": "#20B2AA",        # Light Sea Green
    "Evidence": "#87CEEB"                  # Sky Blue
}

GRAPH_LEGEND = [
    {"label": "Case", "type": "Case", "color": "#FFD700", "description": "Case root entity"},
    {"label": "Evidence (File)", "type": "Evidence", "color": "#87CEEB", "description": "Evidence item (Image, Document, Audio, Video, etc.)"},
    {"label": "Possible Suspect", "type": "Possible Suspect", "color": "#FF7F7F", "description": "Candidate associated via CBIR visual similarity (verification required)"},
    {"label": "Device", "type": "Device", "color": "#DDA0DD", "description": "Hardware device (Phone, Computer, etc.)"}
]


def get_graph_legend():
    """
    Return the standard investigator-facing Graph Legend specification.
    """
    return list(GRAPH_LEGEND)


def get_node_color(node_type):
    for key, color in COLOR_MAP.items():
        if key.lower() in str(node_type).lower():
            return color
    return "#87CEEB"


def visualize_graph(case_id=None, save_path=None, show=True):
    """
    Display the relationship graph with forensic entity color-coding.
    """

    # Build graph
    graph = build_graph(case_id=case_id)

    if graph.number_of_nodes() == 0:
        print(f"No nodes to visualize in graph for case: {case_id}")
        return graph

    # Create figure
    plt.figure(figsize=(12, 9))

    # Generate node positions
    position = nx.spring_layout(graph, seed=42, k=0.8)

    # Determine node colors
    node_colors = [
        get_node_color(graph.nodes[n].get("type", "Evidence"))
        for n in graph.nodes()
    ]

    # Draw nodes and edges
    nx.draw_networkx_nodes(
        graph,
        position,
        node_size=2600,
        node_color=node_colors,
        alpha=0.9
    )

    nx.draw_networkx_edges(
        graph,
        position,
        edge_color="#7F7F7F",
        width=1.5,
        alpha=0.7
    )

    # Format clean, investigator-readable display labels
    clean_labels = {}
    for n in graph.nodes():
        data = graph.nodes[n]
        node_type = str(data.get("type", "")).lower()
        lbl = str(data.get("label", n))
        img_p = data.get("image_path")
        fn = os.path.basename(img_p) if img_p else ""
        src = str(data.get("source", "")).lower()

        is_cbir_person = (
            "possible suspect" in node_type
            or data.get("is_cbir_candidate")
            or data.get("is_cbir_person")
            or (("person" in node_type or "suspect" in node_type or "entity" in node_type) and "cbir" in src)
        )

        if "case" in node_type:
            clean_labels[n] = f"CASE\n{lbl}"
        elif is_cbir_person:
            clean_labels[n] = f"Possible Suspect:\n{lbl}"
        elif "person" in node_type or "suspect" in node_type:
            clean_labels[n] = f"Person:\n{lbl}"
        elif "device" in node_type or "phone" in node_type or "laptop" in node_type or "computer" in node_type:
            clean_labels[n] = f"Device:\n{lbl}"
        elif any(k in node_type for k in ["evidence", "pdf", "document", "audio", "video", "image"]):
            if fn and fn != lbl:
                clean_labels[n] = f"Evidence:\n{lbl}\n{fn}"
            else:
                clean_labels[n] = f"Evidence:\n{lbl}"
        else:
            clean_labels[n] = lbl

    nx.draw_networkx_labels(
        graph,
        position,
        labels=clean_labels,
        font_size=8,
        font_weight="bold"
    )

    # Draw edge labels
    edge_labels = {
        (u, v): d.get("relationship", "")
        for u, v, d in graph.edges(data=True)
        if d.get("relationship")
    }

    if edge_labels:
        nx.draw_networkx_edge_labels(
            graph,
            position,
            edge_labels=edge_labels,
            font_size=7,
            font_color="#333333"
        )

    # Graph Legend: Case, Evidence (File), Possible Suspect, Device
    legend_elements = [
        mpatches.Patch(facecolor="#FFD700", edgecolor="#333333", label="Case"),
        mpatches.Patch(facecolor="#87CEEB", edgecolor="#333333", label="Evidence (File)"),
        mpatches.Patch(facecolor="#FF7F7F", edgecolor="#333333", label="Possible Suspect"),
        mpatches.Patch(facecolor="#DDA0DD", edgecolor="#333333", label="Device"),
    ]
    plt.legend(
        handles=legend_elements,
        loc="upper right",
        title="Graph Legend",
        framealpha=0.9,
        fontsize=8,
        title_fontsize=9
    )

    title = f"Evidence Relationship Graph ({case_id})" if case_id else "Evidence Relationship Graph"
    plt.title(title, fontsize=14, fontweight="bold")
    plt.axis("off")
    plt.tight_layout()

    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches="tight")
        print(f"Graph visualization saved to: {save_path}")

    if show:
        plt.show()

    plt.close()
    return graph


if __name__ == "__main__":
    visualize_graph()
