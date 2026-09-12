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
    Create the CBIR evidence feature table and gracefully migrate legacy schemas.

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

            case_id TEXT NOT NULL DEFAULT 'CASE_DEFAULT',

            evidence_id TEXT NOT NULL DEFAULT '',

            category TEXT,

            image_path TEXT NOT NULL DEFAULT '',

            feature_path TEXT NOT NULL DEFAULT '',

            sha256_hash TEXT,

            description TEXT,

            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

            UNIQUE(case_id, evidence_id)

        )
        """
    )
    connection.commit()

    # --------------------------------------------------------
    # Graceful migration for existing SQLite databases
    # --------------------------------------------------------
    cursor.execute("PRAGMA table_info(image_features)")
    existing_cols = {col[1] for col in cursor.fetchall()}

    columns_to_add = [
        ("case_id", "TEXT NOT NULL DEFAULT 'CASE_DEFAULT'"),
        ("evidence_id", "TEXT NOT NULL DEFAULT ''"),
        ("image_path", "TEXT NOT NULL DEFAULT ''"),
        ("feature_path", "TEXT NOT NULL DEFAULT ''"),
        ("sha256_hash", "TEXT"),
        ("description", "TEXT"),
        ("created_at", "TEXT")
    ]

    for col_name, col_def in columns_to_add:
        if col_name not in existing_cols:
            try:
                cursor.execute(
                    f"ALTER TABLE image_features ADD COLUMN {col_name} {col_def}"
                )
                connection.commit()
            except Exception:
                pass

    # Backfill legacy records if image_name exists
    if "image_name" in existing_cols:
        cursor.execute(
            """
            SELECT id, category, image_name, feature_path, image_path, evidence_id
            FROM image_features
            """
        )
        rows = cursor.fetchall()
        for r_id, cat, img_name, f_path, cur_img_path, cur_ev_id in rows:
            updates = []
            params = []
            if (not cur_ev_id or cur_ev_id == "") and img_name:
                stem = os.path.splitext(str(img_name))[0].replace(" ", "_").upper()
                ev_id = f"EV_{stem}"
                updates.append("evidence_id = ?")
                params.append(ev_id)
            if (not cur_img_path or cur_img_path == "") and img_name and cat:
                possible_path = os.path.join("datasets", "images", str(cat), str(img_name))
                updates.append("image_path = ?")
                params.append(possible_path)
            if updates:
                params.append(r_id)
                cursor.execute(
                    f"UPDATE image_features SET {', '.join(updates)} WHERE id = ?",
                    params
                )
        connection.commit()

    # Backfill SHA-256 for existing evidence records if missing
    try:
        from hash_verifier import compute_sha256
        cursor.execute("SELECT id, image_path FROM image_features WHERE sha256_hash IS NULL OR sha256_hash = ''")
        unhashed = cursor.fetchall()
        for r_id, img_p in unhashed:
            if img_p and os.path.isfile(img_p):
                h = compute_sha256(img_p)
                if h:
                    cursor.execute("UPDATE image_features SET sha256_hash = ? WHERE id = ?", (h, r_id))
        connection.commit()
    except Exception:
        pass

    connection.close()


# ============================================================
# INSERT / UPDATE FEATURE INFORMATION
# ============================================================

def insert_feature(
    case_id,
    evidence_id,
    image_path,
    feature_path,
    category=None,
    sha256_hash=None,
    description=None
):
    """
    Insert or update feature metadata.

    The backend supplies:
        case_id
        evidence_id
        image_path
        feature_path
        category
        sha256_hash (optional, auto-computed if file exists)
        description (optional)

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

    if not sha256_hash and image_path and os.path.isfile(image_path):
        try:
            from hash_verifier import compute_sha256
            sha256_hash = compute_sha256(image_path)
        except Exception:
            sha256_hash = None

    create_table()

    connection = connect_database()
    cursor = connection.cursor()

    cursor.execute(
        """
        SELECT id FROM image_features
        WHERE case_id = ? AND evidence_id = ?
        """,
        (str(case_id), str(evidence_id))
    )
    existing = cursor.fetchone()

    if existing:
        cursor.execute(
            """
            UPDATE image_features
            SET category = ?, image_path = ?, feature_path = ?, sha256_hash = ?, description = ?
            WHERE id = ?
            """,
            (
                category,
                str(image_path),
                str(feature_path),
                sha256_hash,
                description,
                existing[0]
            )
        )
    else:
        cursor.execute(
            """
            INSERT INTO image_features
            (
                case_id,
                evidence_id,
                category,
                image_path,
                feature_path,
                sha256_hash,
                description
            )
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (
                str(case_id),
                str(evidence_id),
                category,
                str(image_path),
                str(feature_path),
                sha256_hash,
                description
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
            created_at,
            sha256_hash,
            description

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
                "created_at": row[4],
                "sha256_hash": row[5],
                "description": row[6]
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
            created_at,
            sha256_hash,
            description

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
        "created_at": row[4],
        "sha256_hash": row[5],
        "description": row[6]
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