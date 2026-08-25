from pydantic import BaseModel
from datetime import datetime
from typing import List


class CyberExpertMyCaseResponse(BaseModel):
    id: int
    case_id: str
    title: str
    description: str | None = None
    investigator_name: str | None = None
    status: str
    priority: str
    assigned_date: datetime
    updated_at: datetime | None = None


class CyberExpertMyCasesPage(BaseModel):
    total: int
    page: int
    limit: int
    cases: List[CyberExpertMyCaseResponse]