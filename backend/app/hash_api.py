from fastapi import FastAPI

from app.routes.hash import router as hash_router


app = FastAPI(
    title="Digital Evidence Hash Generation Module",
    description="Standalone SHA-256 hash generation service for digital evidence.",
    version="1.0.0"
)

app.include_router(hash_router)


@app.get("/")
def home():
    return {
        "module": "Digital Evidence Hash Generation",
        "status": "Running"
    }