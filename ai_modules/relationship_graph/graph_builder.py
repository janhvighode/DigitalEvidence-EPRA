import sqlite3
import networkx as nx 

DATABASE_PATH = "database/graph.db"

def connect_database():
    """
    Connect to the relationship graph database.
    """

    connection = sqlite3.connect(DATABASE_PATH)

    return connection

def build_graph():
    """
    Build a relationship graph from the database.
    """

    # Create an empty graph
    graph = nx.Graph()

    connection = connect_database()

    cursor = connection.cursor()

    cursor.execute("SELECT evidence, suspect, device FROM evidence_links")

    rows = cursor.fetchall()

    connection.close()
    
# Add nodes and edges
    for evidence, suspect, device in rows:

        # Add nodes
        graph.add_node(evidence, type="Evidence")
        graph.add_node(suspect, type="Suspect")
        graph.add_node(device, type="Device")

        # Connect Evidence → Suspect
        graph.add_edge(evidence, suspect)

        # Connect Evidence → Device
        graph.add_edge(evidence, device)
        
    return graph
    
if __name__ == "__main__":

    graph = build_graph()

    print("\n===== GRAPH NODES =====\n")

    for node in graph.nodes(data=True):
        print(node)

    print("\n===== GRAPH EDGES =====\n")

    for edge in graph.edges():
        print(edge)