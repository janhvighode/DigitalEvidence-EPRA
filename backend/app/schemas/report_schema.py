from pydantic import BaseModel, Field
from typing import List


class ReportRequest(BaseModel):
    case_id: str = Field(..., example="CASE-2026-001")
    case_title: str = Field(..., example="Cyber Fraud Investigation")
    investigator_name: str = Field(..., example="Deepak Sharma")
    suspect_name: str = Field(..., example="John Doe")
    evidence_count: int = Field(..., ge=1, example=5)
    events: List[str] = Field(
        ...,
        example=[
            "FIR Registered",
            "Mobile Seized",
            "Laptop Seized",
            "Hash Generated",
            "Report Prepared"
        ]
    )