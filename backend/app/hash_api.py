from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

from app.database import init_db
from app.routes.hash import router as hash_router
from app.routes.evidence_routes import router as evidence_router
from app.routes.report import router as report_router
from app.routes.downstream_routes import router as downstream_router
from app.routes.cbir_routes import router as cbir_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(
    title="Digital Evidence Security, Reporting & CBIR Module",
    description=(
        "Production-grade Security, Cryptographic Integrity, Chain of Custody, "
        "Timeline Reconstruction, PDF Reporting, and Member 3 CBIR Image Retrieval Module "
        "for Digital Evidence Prioritization System."
    ),
    version="2.0.0",
    lifespan=lifespan
)

# Initialize database schema immediately on import
init_db()

# Register route modules
app.include_router(hash_router)
app.include_router(evidence_router)
app.include_router(report_router)
app.include_router(downstream_router)
app.include_router(cbir_router)


def custom_openapi():
    """
    Customize OpenAPI schema so Swagger UI correctly displays UploadFile fields
    as file upload controls.
    """
    if app.openapi_schema:
        return app.openapi_schema

    openapi_schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )

    schemas = openapi_schema.get("components", {}).get("schemas", {})
    for schema in schemas.values():
        properties = schema.get("properties", {})
        for property_name, property_schema in properties.items():
            if property_name == "files" and property_schema.get("type") == "array":
                items = property_schema.get("items", {})
                if items.get("type") == "string":
                    items.pop("contentMediaType", None)
                    items["format"] = "binary"

            if property_name in ("file", "files"):
                if property_schema.get("type") == "string":
                    property_schema.pop("contentMediaType", None)
                    property_schema["format"] = "binary"

    app.openapi_schema = openapi_schema
    return app.openapi_schema


app.openapi = custom_openapi


@app.get("/")
def home():
    return {
        "module": "Digital Evidence Security & Reporting Module (Member 5)",
        "status": "Running",
        "version": "2.0.0",
        "subsystems": {
            "hash_and_manifest": "/hash",
            "evidence_lifecycle": "/evidence",
            "reporting": "/report",
            "downstream_contract": "/downstream",
            "cbir_retrieval": "/cbir"
        }
    }