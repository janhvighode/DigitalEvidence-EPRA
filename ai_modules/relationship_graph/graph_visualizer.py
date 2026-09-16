import os
import textwrap
import numpy as np
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


def visualize_graph(graph=None, case_id=None, save_path=None, output_path=None, show=False):
    """
    Display the relationship graph with forensic entity color-coding,
    clean non-overlapping relationship labels, parallel edge curved arcs,
    and deduplicated relationships.
    """
    if isinstance(graph, str) and case_id is None:
        case_id = graph
        graph = None

    if save_path is None and output_path is not None:
        save_path = output_path

    if graph is None:
        graph = build_graph(case_id=case_id)

    if graph.number_of_nodes() == 0:
        print(f"No nodes to visualize in graph for case: {case_id}")
        return graph

    fig, ax = plt.subplots(figsize=(14, 10))

    # 1. Layout positioning: Fix Case node at center (0, 0) if present
    case_nodes = [
        n for n, d in graph.nodes(data=True)
        if "case" in str(d.get("type", "")).lower()
    ]
    case_node_id = case_nodes[0] if case_nodes else (str(case_id) if case_id and graph.has_node(str(case_id)) else None)

    if case_node_id and graph.has_node(case_node_id):
        fixed_pos = {case_node_id: np.array([0.0, 0.0])}
        position = nx.spring_layout(
            graph,
            pos=fixed_pos,
            fixed=[case_node_id],
            seed=42,
            k=1.6,
            iterations=120
        )
    else:
        position = nx.spring_layout(graph, seed=42, k=1.5, iterations=100)

    # 2. Determine node colors and sizes
    node_colors = [
        get_node_color(graph.nodes[n].get("type", "Evidence"))
        for n in graph.nodes()
    ]
    node_sizes = [
        3200 if (case_node_id and n == case_node_id) else 2600
        for n in graph.nodes()
    ]

    nx.draw_networkx_nodes(
        graph,
        position,
        node_size=node_sizes,
        node_color=node_colors,
        alpha=0.92,
        edgecolors="#333333",
        linewidths=1.2,
        ax=ax
    )

    # 3. Format clean, wrapped investigator-readable display labels
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

        # Wrap long text so it fits neatly within the node circles
        display_text = lbl
        if len(display_text) > 22:
            display_text = display_text[:20] + "..."
        wrapped = "\n".join(textwrap.wrap(display_text, width=12))

        if "case" in node_type:
            clean_labels[n] = f"CASE\n{wrapped}"
        elif is_cbir_person:
            clean_labels[n] = f"Possible Suspect:\n{wrapped}"
        elif "person" in node_type or "suspect" in node_type:
            clean_labels[n] = f"Person:\n{wrapped}"
        elif "device" in node_type or "phone" in node_type or "laptop" in node_type or "computer" in node_type:
            clean_labels[n] = f"Device:\n{wrapped}"
        elif any(k in node_type for k in ["evidence", "pdf", "document", "audio", "video", "image"]):
            clean_labels[n] = f"Evidence:\n{wrapped}"
        else:
            clean_labels[n] = wrapped

    nx.draw_networkx_labels(
        graph,
        position,
        labels=clean_labels,
        font_size=7.5,
        font_weight="bold",
        font_color="#111111",
        ax=ax
    )

    # 4. Group and deduplicate edges before rendering
    # Identity: tuple(sorted([u, v])) + (relationship_type,)
    seen_rendered_edges = set()
    case_edges = []
    duplicate_edges = []
    cbir_edges = []
    other_edges = []
    parallel_edges = []  # pairs with > 1 distinct relationship type

    for u, v, d in graph.edges(data=True):
        all_rels = d.get("parallel_relationships", [d])
        is_parallel_pair = len(all_rels) > 1

        for idx, rel_item in enumerate(all_rels):
            rel_type = rel_item.get("relationship_type", rel_item.get("relationship", "ASSOCIATION"))
            rel_name = rel_item.get("relationship", rel_type)

            stable_key = tuple(sorted([str(u), str(v)])) + (rel_type,)
            if stable_key in seen_rendered_edges:
                continue
            seen_rendered_edges.add(stable_key)

            edge_tuple = (u, v, rel_name, rel_type, rel_item)

            if is_parallel_pair:
                parallel_edges.append((u, v, rel_name, rel_type, idx, len(all_rels), rel_item))
            elif (case_node_id and (u == case_node_id or v == case_node_id)) or rel_type == "BELONGS_TO_CASE":
                case_edges.append(edge_tuple)
            elif rel_type == "EXACT_FILE_DUPLICATE":
                duplicate_edges.append(edge_tuple)
            elif rel_type == "CBIR_VISUAL_RELATIONSHIP":
                cbir_edges.append(edge_tuple)
            else:
                other_edges.append(edge_tuple)

    # 5. Draw single non-case edges
    if other_edges:
        nx.draw_networkx_edges(
            graph,
            position,
            edgelist=[(u, v) for u, v, _, _, _ in other_edges],
            edge_color="#555555",
            width=1.8,
            alpha=0.8,
            ax=ax
        )
        other_labels = {(u, v): rel_name for u, v, rel_name, _, _ in other_edges}
        nx.draw_networkx_edge_labels(
            graph,
            position,
            edge_labels=other_labels,
            label_pos=0.5,
            font_size=7.0,
            font_color="#222222",
            font_weight="bold",
            bbox=dict(boxstyle="round,pad=0.25", fc="#FAFAFA", ec="#888888", lw=0.8, alpha=0.95),
            ax=ax
        )

    # 6. Draw Exact Duplicate edges (Forest Green)
    if duplicate_edges:
        nx.draw_networkx_edges(
            graph,
            position,
            edgelist=[(u, v) for u, v, _, _, _ in duplicate_edges],
            edge_color="#2E7D32",
            width=2.4,
            alpha=0.9,
            ax=ax
        )
        dup_labels = {(u, v): rel_name for u, v, rel_name, _, _ in duplicate_edges}
        nx.draw_networkx_edge_labels(
            graph,
            position,
            edge_labels=dup_labels,
            label_pos=0.5,
            font_size=7.0,
            font_color="#1B5E20",
            font_weight="bold",
            bbox=dict(boxstyle="round,pad=0.25", fc="#F1F8E9", ec="#2E7D32", lw=1.0, alpha=0.95),
            ax=ax
        )

    # 7. Draw CBIR Visual Relationship edges (Royal Blue Dashed)
    if cbir_edges:
        nx.draw_networkx_edges(
            graph,
            position,
            edgelist=[(u, v) for u, v, _, _, _ in cbir_edges],
            edge_color="#1565C0",
            width=2.0,
            style="--",
            alpha=0.85,
            ax=ax
        )
        cbir_labels = {(u, v): rel_name for u, v, rel_name, _, _ in cbir_edges}
        nx.draw_networkx_edge_labels(
            graph,
            position,
            edge_labels=cbir_labels,
            label_pos=0.5,
            font_size=7.0,
            font_color="#0D47A1",
            font_weight="bold",
            bbox=dict(boxstyle="round,pad=0.25", fc="#E3F2FD", ec="#1565C0", lw=1.0, alpha=0.95),
            ax=ax
        )

    # 8. Draw Case radial edges (BELONGS_TO_CASE) with staggered collision-free label positions
    if case_edges:
        nx.draw_networkx_edges(
            graph,
            position,
            edgelist=[(u, v) for u, v, _, _, _ in case_edges],
            edge_color="#A5A5A5",
            width=1.4,
            alpha=0.65,
            ax=ax
        )
        for i, (u, v, rel_name, _, _) in enumerate(case_edges):
            # Stagger label along radial edge (alternate 0.65 and 0.78 towards outer node)
            # This eliminates clumping and label overlapping near the central Case node
            lp = 0.65 if (i % 2 == 0) else 0.78
            nx.draw_networkx_edge_labels(
                graph,
                position,
                edge_labels={(u, v): rel_name},
                label_pos=lp,
                font_size=6.5,
                font_color="#4F4F4F",
                bbox=dict(boxstyle="round,pad=0.2", fc="white", ec="#DCDCDC", lw=0.6, alpha=0.92),
                ax=ax
            )

    # 9. Draw Parallel Edges (multiple distinct relationship types between same pair) using curved arcs
    if parallel_edges:
        for u, v, rel_name, rel_type, idx, total_rels, _ in parallel_edges:
            rad = 0.22 if (idx % 2 == 0) else -0.22
            p_color = "#2E7D32" if rel_type == "EXACT_FILE_DUPLICATE" else ("#1565C0" if rel_type == "CBIR_VISUAL_RELATIONSHIP" else "#555555")
            p_style = "--" if rel_type == "CBIR_VISUAL_RELATIONSHIP" else "-"
            nx.draw_networkx_edges(
                graph,
                position,
                edgelist=[(u, v)],
                connectionstyle=f"arc3, rad={rad}",
                edge_color=p_color,
                style=p_style,
                width=1.8,
                alpha=0.85,
                arrows=True,
                arrowstyle="-",
                ax=ax
            )
            # Calculate curved midpoint for label placement
            p1, p2 = np.array(position[u]), np.array(position[v])
            mid = (p1 + p2) / 2.0
            diff = p2 - p1
            length = np.linalg.norm(diff)
            if length > 1e-6:
                normal = np.array([-diff[1], diff[0]]) / length
                offset_pos = mid + (rad * 0.5 * length) * normal
            else:
                offset_pos = mid

            ax.text(
                offset_pos[0], offset_pos[1], rel_name,
                fontsize=6.8,
                fontweight="bold",
                color="#222222",
                ha="center",
                va="center",
                bbox=dict(boxstyle="round,pad=0.22", fc="#FAFAFA", ec=p_color, lw=0.8, alpha=0.95)
            )

    # 10. Graph Legend
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
    ax.axis("off")
    plt.tight_layout()

    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches="tight")
        print(f"Graph visualization saved to: {save_path}")

    if show:
        plt.show()

    plt.close(fig)
    return graph


if __name__ == "__main__":
    visualize_graph()

