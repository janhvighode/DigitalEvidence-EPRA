import sqlite3
import networkx as nx 

DATABASE_PATH = "database/graph.db"

def connect_database():
    """
    Connect to the relationship graph database.
    """

    connection = sqlite3.connect(DATABASE_PATH)

    return connection

def build_graph(case_id=None, cbir_relationships=None):
    """
    Build a relationship graph from the database with case isolation.
    """
    if case_id:
        from case_graph_engine import build_case_relationship_graph
        return build_case_relationship_graph(case_id, cbir_relationships)

    # Legacy fallback: build graph across all available records
    graph = nx.Graph()
    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute("SELECT evidence, suspect, device FROM evidence_links")
    rows = cursor.fetchall()
    connection.close()

    for evidence, suspect, device in rows:
        if evidence:
            graph.add_node(evidence, type="Evidence")
        if suspect:
            graph.add_node(suspect, type="Suspect")
        if device:
            graph.add_node(device, type="Device")

        if evidence and suspect:
            graph.add_edge(evidence, suspect, relationship="ASSOCIATED_WITH")
        if evidence and device:
            graph.add_edge(evidence, device, relationship="STORED_ON_DEVICE")
        if suspect and device:
            graph.add_edge(device, suspect, relationship="OWNED_OR_USED_BY")

    return graph
    
if __name__ == "__main__":

    graph = build_graph()

    print("\n===== GRAPH NODES =====\n")

    for node in graph.nodes(data=True):
        print(node)

    print("\n===== GRAPH EDGES =====\n")

    for edge in graph.edges():
        print(edge)