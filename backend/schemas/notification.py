from typing import List
from datetime import datetime
from pydantic import BaseModel


class NotificationResponse(BaseModel):
    id: int
    title: str
    message: str
    type: str
    is_read: bool
    created_at: datetime

    class Config:
        from_attributes = True


class NotificationCountResponse(BaseModel):
    count: int


class NotificationListPage(BaseModel):
    page: int
    limit: int
    total: int
    unread_count: int
    items: List[NotificationResponse]


class NotificationActionResponse(BaseModel):
    message: str
    updated_count: int = 1