from fastapi import FastAPI
from fastapi.openapi.utils import get_openapi

from app.routes.hash import router as hash_router


app = FastAPI(
    title="Digital Evidence Hash Generation Module",
    description="Standalone SHA-256 hash generation service for digital evidence.",
    version="1.0.0"
)


# Register hash routes
app.include_router(hash_router)


def custom_openapi():
    """
    Customize OpenAPI schema so Swagger UI correctly
    displays UploadFile fields as file upload controls.
    """

    if app.openapi_schema:
        return app.openapi_schema

    openapi_schema = get_openapi(
        title=app.title,
        version=app.version,
        description=app.description,
        routes=app.routes,
    )

    # Fix file upload schema for Swagger UI
    schemas = openapi_schema.get("components", {}).get("schemas", {})

    for schema in schemas.values():

        properties = schema.get("properties", {})

        for property_name, property_schema in properties.items():

            # Multiple file upload
            if (
                property_name == "files"
                and property_schema.get("type") == "array"
            ):

                items = property_schema.get("items", {})

                if items.get("type") == "string":

                    items.pop("contentMediaType", None)
                    items["format"] = "binary"

            # Single file upload
            if property_name == "file":

                if property_schema.get("type") == "string":

                    property_schema.pop(
                        "contentMediaType",
                        None
                    )

                    property_schema["format"] = "binary"

    app.openapi_schema = openapi_schema

    return app.openapi_schema


app.openapi = custom_openapi


@app.get("/")
def home():

    return {
        "module": "Digital Evidence Hash Generation",
        "status": "Running"
    }