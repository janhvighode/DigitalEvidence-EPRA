import os
import sqlite3
from pathlib import Path
from sqlalchemy import create_engine, text
from sqlalchemy.orm import declarative_base, sessionmaker

# Configurable storage and database locations
BASE_DIR = Path(__file__).resolve().parent
DEFAULT_STORAGE_DIR = BASE_DIR / "uploads"
DEFAULT_DB_PATH = BASE_DIR / "evidence_vault.db"

STORAGE_DIR = Path(os.getenv("EVIDENCE_STORAGE_DIR", str(DEFAULT_STORAGE_DIR)))
UPLOAD_HASH_INPUT_DIR = STORAGE_DIR / "hash_input"
UPLOAD_HASH_BATCH_DIR = STORAGE_DIR / "hash_batch"
MANIFEST_DIR = STORAGE_DIR / "hash_manifests"
REPORTS_DIR = STORAGE_DIR / "reports"

# Ensure all directories exist
for directory in [STORAGE_DIR, UPLOAD_HASH_INPUT_DIR, UPLOAD_HASH_BATCH_DIR, MANIFEST_DIR, REPORTS_DIR]:
    directory.mkdir(parents=True, exist_ok=True)

DATABASE_URL = os.getenv(
    "EVIDENCE_DB_URL",
    f"sqlite:///{DEFAULT_DB_PATH.as_posix()}"
)

connect_args = {}
if DATABASE_URL.startswith("sqlite"):
    connect_args["check_same_thread"] = False

engine = create_engine(
    DATABASE_URL,
    connect_args=connect_args,
    echo=False
)

SessionLocal = sessionmaker(
    autocommit=False,
    autoflush=False,
    bind=engine
)

Base = declarative_base()


def get_db():
    """
    FastAPI dependency yielding an isolated database session.
    """
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def upgrade_schema(target_engine=None):
    """
    Non-destructive schema upgrade.
    Inspects existing tables and performs ALTER TABLE ADD COLUMN for missing fields.
    Never drops tables or erases historical records.
    Backfills external IDs and backend hashes for existing legacy records.
    """
    if target_engine is None:
        target_engine = engine

    # Import all models to register them
    import app.models  # noqa: F401
    Base.metadata.create_all(bind=target_engine)

    # Column definitions to add if missing
    columns_to_add = {
        "evidence_records": [
            ("external_evidence_id", "VARCHAR(100)"),
            ("external_source", "VARCHAR(100) DEFAULT 'shared_backend'"),
            ("mime_type_source", "VARCHAR(100)"),
            ("original_sha256", "VARCHAR(64)"),
            ("current_sha256", "VARCHAR(64)"),
            ("verification_status", "VARCHAR(50)"),
            ("verification_timestamp", "DATETIME"),
            ("verification_source", "VARCHAR(100)"),
            ("verification_notes", "VARCHAR(500)"),
            ("created_at", "DATETIME"),
            ("created_at_source", "VARCHAR(100)"),
            ("modified_at", "DATETIME"),
            ("modified_at_source", "VARCHAR(100)"),
            ("accessed_at", "DATETIME"),
            ("accessed_at_source", "VARCHAR(100)"),
            ("retrieved_at", "DATETIME"),
            ("cached_at", "DATETIME"),
        ],
        "custody_logs": [
            ("external_event_id", "VARCHAR(100)"),
            ("event_type", "VARCHAR(50)"),
            ("title", "VARCHAR(150)"),
            ("actor_role", "VARCHAR(100)"),
            ("related_reference", "VARCHAR(64)"),
            ("source_reference", "VARCHAR(100)"),
            ("recorded_at", "DATETIME"),
        ],
        "report_records": [
            ("report_type", "VARCHAR(100) DEFAULT 'Comprehensive Forensic Report'"),
            ("file_format", "VARCHAR(20) DEFAULT 'PDF'"),
            ("file_size_bytes", "BIGINT DEFAULT 0"),
            ("selected_sections", "TEXT"),
            ("crime_type", "VARCHAR(100)"),
            ("generated_by_id", "VARCHAR(100)"),
            ("generated_by_role", "VARCHAR(100)"),
            ("is_draft", "BOOLEAN DEFAULT 0"),
        ],
        "activity_logs": [
            ("external_evidence_id", "VARCHAR(100)"),
            ("external_source", "VARCHAR(100) DEFAULT 'SHARED_BACKEND'"),
        ]
    }

    with target_engine.connect() as conn:
        for table_name, cols in columns_to_add.items():
            # Check if table exists
            try:
                res = conn.execute(text(f"PRAGMA table_info({table_name})")).fetchall()
            except Exception:
                continue
            existing_cols = {row[1] for row in res}

            for col_name, col_type in cols:
                if col_name not in existing_cols:
                    try:
                        conn.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {col_name} {col_type}"))
                        conn.commit()
                    except Exception:
                        pass

        # Backfill existing legacy records non-destructively
        try:
            # Backfill external_evidence_id with local id string if null
            conn.execute(text(
                "UPDATE evidence_records SET external_evidence_id = CAST(id AS TEXT) "
                "WHERE external_evidence_id IS NULL"
            ))

            conn.execute(text(
                "UPDATE activity_logs SET external_evidence_id = CAST(evidence_id AS TEXT) "
                "WHERE external_evidence_id IS NULL AND evidence_id IS NOT NULL"
            ))

            # Backfill original_sha256 from evidence_hashes if null
            conn.execute(text(
                "UPDATE evidence_records SET original_sha256 = ("
                "  SELECT sha256_hash FROM evidence_hashes "
                "  WHERE evidence_hashes.evidence_id = evidence_records.id LIMIT 1"
                ") WHERE original_sha256 IS NULL AND EXISTS ("
                "  SELECT 1 FROM evidence_hashes WHERE evidence_hashes.evidence_id = evidence_records.id"
                ")"
            ))

            # Backfill verification_status from integrity_logs if null
            conn.execute(text(
                "UPDATE evidence_records SET verification_status = ("
                "  SELECT outcome FROM integrity_logs "
                "  WHERE integrity_logs.evidence_id = evidence_records.id "
                "  ORDER BY verified_at DESC LIMIT 1"
                ") WHERE verification_status IS NULL AND EXISTS ("
                "  SELECT 1 FROM integrity_logs WHERE integrity_logs.evidence_id = evidence_records.id"
                ")"
            ))
            conn.commit()
        except Exception:
            pass


def init_db():
    """
    Initialize and upgrade database schema non-destructively.
    """
    import app.models  # noqa: F401
    upgrade_schema(engine)
