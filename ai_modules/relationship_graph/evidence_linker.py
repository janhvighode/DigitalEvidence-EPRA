import sqlite3

DATABASE_PATH = "database/graph.db"

def connect_database():
    """
    Connect to the relationship graph database.
    """

    connection = sqlite3.connect(DATABASE_PATH)

    return connection
def create_table():
    """
    Create evidence_links table if it doesn't exist.
    """

    connection = connect_database()

    cursor = connection.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS evidence_links (

            id INTEGER PRIMARY KEY AUTOINCREMENT,

            evidence TEXT,

            suspect TEXT,

            device TEXT

        )
    """)

    connection.commit()

    connection.close()

    print("Evidence table created successfully!")
    

    
def insert_link(evidence, suspect, device):
    """
    Insert an evidence relationship into the database.
    """

    connection = connect_database()

    cursor = connection.cursor()

    cursor.execute("""
        INSERT INTO evidence_links
        (evidence, suspect, device)
        VALUES (?, ?, ?)
    """, (evidence, suspect, device))

    connection.commit()

    connection.close()

    print(f"Inserted: {evidence}")
    
def view_links():
    """
    Display all evidence relationships stored in the database.
    """

    connection = connect_database()

    cursor = connection.cursor()

    cursor.execute("SELECT * FROM evidence_links")

    rows = cursor.fetchall()

    connection.close()

    print("\n===== Evidence Relationships =====\n")

    for row in rows:
        print(f"ID       : {row[0]}")
        print(f"Evidence : {row[1]}")
        print(f"Suspect  : {row[2]}")
        print(f"Device   : {row[3]}")
        print("-" * 40)
    
if __name__ == "__main__":

    create_table()

    insert_link(
        "person1.jpg",
        "Rahul Sharma",
        "Samsung Galaxy S23"
    )

    view_links()