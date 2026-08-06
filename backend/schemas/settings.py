from pydantic import BaseModel


class SettingsResponse(BaseModel):

    email_notifications: bool

    browser_notifications: bool

    auto_logout: int

    class Config:
        from_attributes = True


class SettingsUpdate(BaseModel):

    email_notifications: bool

    browser_notifications: bool

    auto_logout: int