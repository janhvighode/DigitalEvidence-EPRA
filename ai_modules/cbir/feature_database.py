# ============================================================
# Digital Evidence EPRA
# Module : CBIR
# File   : feature_database.py
# Purpose: Dynamic feature database access for CBIR
# Author : Member 3 (Trisha)
# ============================================================

import os
import sqlite3


# ============================================================
# DATABASE CONFIGURATION
# ============================================================

DATABASE_PATH = os.getenv(
    "CBIR_DATABASE_PATH",
    "database/images.db"
)


# ============================================================
# DATABASE CONNECTION
# ============================================================

def connect_database():
    """
    Connect to the CBIR feature database.
    Creates the database directory if required.
    """

    database_directory = os.path.dirname(
        DATABASE_PATH
    )

    if database_directory:
        os.makedirs(
            database_directory,
            exist_ok=True
        )

    return sqlite3.connect(
        DATABASE_PATH
    )


# ============================================================
# CREATE FEATURE TABLE
# ============================================================

def create_table():
    """
    Create the CBIR evidence feature table.

    One evidence item is uniquely identified by:
        case_id + evidence_id

    This prevents the same evidence ID from being
    accidentally associated with multiple records
    inside the same case.
    """

    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute(
        """
        CREATE TABLE IF NOT EXISTS image_features (

            id INTEGER PRIMARY KEY AUTOINCREMENT,

            case_id TEXT NOT NULL,

            evidence_id TEXT NOT NULL,

            category TEXT,

            image_path TEXT NOT NULL,

            feature_path TEXT NOT NULL,

            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

            UNIQUE(case_id, evidence_id)

        )
        """
    )

    connection.commit()
    connection.close()


# ============================================================
# INSERT / UPDATE FEATURE INFORMATION
# ============================================================

def insert_feature(
    case_id,
    evidence_id,
    image_path,
    feature_path,
    category=None
):
    """
    Insert or update feature metadata.

    The backend supplies:
        case_id
        evidence_id
        image_path
        feature_path
        category

    No case or evidence information is hardcoded.
    """

    if not case_id:
        raise ValueError(
            "case_id is required."
        )

    if not evidence_id:
        raise ValueError(
            "evidence_id is required."
        )

    if not image_path:
        raise ValueError(
            "image_path is required."
        )

    if not feature_path:
        raise ValueError(
            "feature_path is required."
        )

    create_table()

    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute(
        """
        INSERT INTO image_features
        (
            case_id,
            evidence_id,
            category,
            image_path,
            feature_path
        )
        VALUES (?, ?, ?, ?, ?)

        ON CONFLICT(case_id, evidence_id)
        DO UPDATE SET
            category = excluded.category,
            image_path = excluded.image_path,
            feature_path = excluded.feature_path
        """,
        (
            str(case_id),
            str(evidence_id),
            category,
            str(image_path),
            str(feature_path)
        )
    )

    connection.commit()
    connection.close()


# ============================================================
# GET ALL EVIDENCE FOR SELECTED CASE
# ============================================================

def get_case_evidence(case_id):
    """
    Retrieve ONLY evidence belonging to the selected case.

    This function is used by the CBIR service.

    Evidence from another case is never returned.
    """

    if not case_id:
        return []

    create_table()

    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute(
        """
        SELECT
            evidence_id,
            category,
            image_path,
            feature_path,
            created_at

        FROM image_features

        WHERE case_id = ?

        ORDER BY created_at ASC
        """,
        (
            str(case_id),
        )
    )

    rows = cursor.fetchall()

    connection.close()

    evidence = []

    for row in rows:

        evidence.append(
            {
                "evidence_id": row[0],
                "category": row[1],
                "image_path": row[2],
                "feature_path": row[3],
                "created_at": row[4]
            }
        )

    return evidence


# ============================================================
# GET ONE EVIDENCE ITEM
# ============================================================

def get_evidence(
    case_id,
    evidence_id
):
    """
    Retrieve one evidence item.

    BOTH case_id and evidence_id are required.

    This prevents an evidence item from another case
    being accidentally selected.
    """

    if not case_id or not evidence_id:
        return None

    create_table()

    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute(
        """
        SELECT
            evidence_id,
            category,
            image_path,
            feature_path,
            created_at

        FROM image_features

        WHERE case_id = ?
        AND evidence_id = ?

        LIMIT 1
        """,
        (
            str(case_id),
            str(evidence_id)
        )
    )

    row = cursor.fetchone()

    connection.close()

    if row is None:
        return None

    return {
        "evidence_id": row[0],
        "category": row[1],
        "image_path": row[2],
        "feature_path": row[3],
        "created_at": row[4]
    }


# ============================================================
# GET FEATURE PATH
# ============================================================

def get_feature_path(
    case_id,
    evidence_id
):
    """
    Return the feature file associated with
    the selected evidence.
    """

    evidence = get_evidence(
        case_id,
        evidence_id
    )

    if evidence is None:
        return None

    return evidence["feature_path"]


# ============================================================
# CHECK WHETHER EVIDENCE EXISTS
# ============================================================

def evidence_exists(
    case_id,
    evidence_id
):
    """
    Check whether the specified evidence belongs
    to the specified case.
    """

    return (
        get_evidence(
            case_id,
            evidence_id
        )
        is not None
    )


# ============================================================
# DELETE ONE EVIDENCE FEATURE RECORD
# ============================================================

def delete_evidence(
    case_id,
    evidence_id
):
    """
    Delete only the CBIR metadata record for the
    specified evidence inside the specified case.

    This function does NOT delete the original evidence file.
    """

    if not case_id or not evidence_id:
        return False

    create_table()

    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute(
        """
        DELETE FROM image_features

        WHERE case_id = ?
        AND evidence_id = ?
        """,
        (
            str(case_id),
            str(evidence_id)
        )
    )

    deleted = (
        cursor.rowcount > 0
    )

    connection.commit()
    connection.close()

    return deleted


# ============================================================
# COUNT CASE EVIDENCE
# ============================================================

def count_case_evidence(
    case_id
):
    """
    Return the number of evidence items
    belonging to a case.
    """

    if not case_id:
        return 0

    create_table()

    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute(
        """
        SELECT COUNT(*)

        FROM image_features

        WHERE case_id = ?
        """,
        (
            str(case_id),
        )
    )

    count = cursor.fetchone()[0]

    connection.close()

    return int(count)


# ============================================================
# DATABASE TEST
# ============================================================

if __name__ == "__main__":

    print("=" * 70)
    print("DIGITAL EVIDENCE EPRA")
    print("CBIR FEATURE DATABASE")
    print("=" * 70)

    create_table()

    print()
    print(
        f"Database : {DATABASE_PATH}"
    )

    print(
        "Feature database table is ready."
    )

    print(
        "Case and evidence information are supplied dynamically."
    )

    print("=" * 70)