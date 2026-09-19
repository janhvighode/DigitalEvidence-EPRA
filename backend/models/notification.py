from sqlalchemy import (
    Column,
    Integer,
    String,
    Boolean,
    DateTime,
    ForeignKey
)
from sqlalchemy.sql import func

from database.database import Base
import models.cyber_cell  # Ensure ForeignKey target table registration
import models.user        # Ensure ForeignKey target table registration



class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, index=True)

    title = Column(String(255), nullable=False)

    message = Column(String(500), nullable=False)

    type = Column(String(50), nullable=False)

    # Specific user notification
    user_id = Column(
        Integer,
        ForeignKey("users.id"),
        nullable=True
    )

    # Branch-specific notification
    cyber_cell_id = Column(
        Integer,
        ForeignKey("cyber_cells.id"),
        nullable=True
    )

    is_read = Column(Boolean, default=False)

    created_at = Column(
        DateTime,
        server_default=func.now()
    )

    @property
    def case_id(self):
        import re
        text = f"{self.title or ''} {self.message or ''}"
        match = re.search(r"\b(CASE-[A-Za-z0-9_-]+)\b", text, re.IGNORECASE)
        if match:
            return match.group(1)
        match2 = re.search(r"\bcase\s+([A-Za-z0-9_-]+)", text, re.IGNORECASE)
        if match2:
            return match2.group(1).rstrip(".").strip()
        return None

    @property
    def evidence_id(self):
        import re
        text = f"{self.title or ''} {self.message or ''}"
        match = re.search(r"\b(EV-[A-Za-z0-9_-]+)\b", text, re.IGNORECASE)
        if match:
            return match.group(1)
        match2 = re.search(r"evidence\s+#?([A-Za-z0-9_-]+)", text, re.IGNORECASE)
        if match2:
            return match2.group(1)
        return None

    @property
    def read_at(self):
        return None
