from evidence_linker import view_links
from graph_builder import build_graph
from graph_visualizer import visualize_graph


def run_graph_service():
    """
    Run the complete Relationship Graph module.
    """

    print("\n===== Evidence Relationships =====")
    view_links()

    print("\nBuilding relationship graph...")
    graph = build_graph()

    print(f"\nGraph created successfully!")
    print(f"Total Nodes : {graph.number_of_nodes()}")
    print(f"Total Edges : {graph.number_of_edges()}")

    print("\nOpening graph visualization...")
    visualize_graph()


if __name__ == "__main__":
    run_graph_service()