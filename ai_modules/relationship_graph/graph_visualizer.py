import matplotlib.pyplot as plt
import networkx as nx
from graph_builder import build_graph


def visualize_graph():
    """
    Display the relationship graph.
    """

    # Build graph
    graph = build_graph()

    # Create figure
    plt.figure(figsize=(10, 8))

    # Generate node positions
    position = nx.spring_layout(graph, seed=42)

    # Draw graph
    nx.draw(
        graph,
        position,
        with_labels=True,
        node_size=2500,
        node_color="lightblue",
        font_size=9,
        font_weight="bold",
        edge_color="gray"
    )

    # Graph title
    plt.title("Evidence Relationship Graph")

    # Display graph
    plt.show()


if __name__ == "__main__":
    visualize_graph()