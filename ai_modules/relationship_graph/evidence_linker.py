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
    Create evidence_links table if it doesn't exist and migrate schema.
    """

    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute("""
        CREATE TABLE IF NOT EXISTS evidence_links (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            case_id TEXT DEFAULT 'CASE_DEFAULT',
            evidence TEXT,
            evidence_type TEXT DEFAULT 'Evidence',
            suspect TEXT,
            device TEXT,
            confidence REAL DEFAULT 1.0,
            relationship_type TEXT DEFAULT 'ASSOCIATED_WITH',
            verification_required INTEGER DEFAULT 1
        )
    """)
    connection.commit()

    # Graceful migration for existing database
    cursor.execute("PRAGMA table_info(evidence_links)")
    existing_cols = {col[1] for col in cursor.fetchall()}

    columns_to_add = [
        ("case_id", "TEXT DEFAULT 'CASE_DEFAULT'"),
        ("evidence_type", "TEXT DEFAULT 'Evidence'"),
        ("confidence", "REAL DEFAULT 1.0"),
        ("relationship_type", "TEXT DEFAULT 'ASSOCIATED_WITH'"),
        ("verification_required", "INTEGER DEFAULT 1")
    ]

    for col_name, col_def in columns_to_add:
        if col_name not in existing_cols:
            try:
                cursor.execute(f"ALTER TABLE evidence_links ADD COLUMN {col_name} {col_def}")
                connection.commit()
            except Exception:
                pass

    connection.close()
    print("Evidence table created and verified successfully!")


def insert_link(
    evidence,
    suspect,
    device,
    case_id="CASE_DEFAULT",
    evidence_type="Evidence",
    confidence=1.0,
    relationship_type="ASSOCIATED_WITH",
    verification_required=1
):
    """
    Insert an evidence relationship into the database with case isolation.
    """

    create_table()
    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute("""
        INSERT INTO evidence_links
        (case_id, evidence, evidence_type, suspect, device, confidence, relationship_type, verification_required)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (
        str(case_id),
        str(evidence),
        str(evidence_type),
        str(suspect),
        str(device),
        float(confidence),
        str(relationship_type),
        1 if verification_required else 0
    ))

    connection.commit()
    connection.close()

    print(f"Inserted link in case '{case_id}': {evidence} <-> {suspect} <-> {device}")


def get_case_links(case_id):
    """
    Retrieve evidence relationships strictly belonging to the selected case.
    """

    if not case_id:
        return []

    create_table()
    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute("""
        SELECT id, case_id, evidence, evidence_type, suspect, device, confidence, relationship_type, verification_required
        FROM evidence_links
        WHERE case_id = ?
    """, (str(case_id),))

    rows = cursor.fetchall()
    connection.close()

    links = []
    for r in rows:
        links.append({
            "id": r[0],
            "case_id": r[1],
            "evidence": r[2],
            "evidence_type": r[3] or "Evidence",
            "suspect": r[4],
            "device": r[5],
            "confidence": float(r[6]) if r[6] is not None else 1.0,
            "relationship_type": r[7] or "ASSOCIATED_WITH",
            "verification_required": bool(r[8])
        })

    return links


def view_links(case_id=None):
    """
    Display evidence relationships stored in the database.
    """

    create_table()
    connection = connect_database()
    cursor = connection.cursor()

    if case_id:
        cursor.execute("SELECT id, case_id, evidence, suspect, device FROM evidence_links WHERE case_id = ?", (str(case_id),))
    else:
        cursor.execute("SELECT id, case_id, evidence, suspect, device FROM evidence_links")

    rows = cursor.fetchall()
    connection.close()

    print("\n===== Evidence Relationships =====\n")
    for row in rows:
        print(f"ID       : {row[0]}")
        print(f"Case     : {row[1]}")
        print(f"Evidence : {row[2]}")
        print(f"Suspect  : {row[3]}")
        print(f"Device   : {row[4]}")
        print("-" * 40)


if __name__ == "__main__":
    create_table()
    insert_link(
        evidence="EV_PERSON_1",
        suspect="Rahul Sharma",
        device="Samsung Galaxy S23",
        case_id="CASE_TEST_01",
        evidence_type="Image",
        confidence=1.0,
        relationship_type="RECOVERED_FROM_DEVICE"
    )
    view_links("CASE_TEST_01")