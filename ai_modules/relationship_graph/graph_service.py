from evidence_linker import view_links
from graph_builder import build_graph
from graph_visualizer import visualize_graph


def run_graph_service(case_id="CASE_DEFAULT", save_path=None, show=False):
    """
    Run the complete Relationship Graph module for a case.
    """

    print(f"\n===== Evidence Relationships (Case: {case_id}) =====")
    view_links(case_id=case_id)

    print(f"\nBuilding relationship graph for case '{case_id}'...")
    graph = build_graph(case_id=case_id)

    print(f"\nGraph created successfully!")
    print(f"Total Nodes : {graph.number_of_nodes()}")
    print(f"Total Edges : {graph.number_of_edges()}")

    print("\nVisualizing graph...")
    visualize_graph(case_id=case_id, save_path=save_path, show=show)

    return graph


if __name__ == "__main__":
    run_graph_service("CASE_DEFAULT", show=False)