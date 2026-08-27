from sqlalchemy.orm import Session
from models.case import Case
from schemas.case import CaseCreate
import random


def generate_case_id():
    number = random.randint(1000, 9999)
    return f"CASE-{number}"


def create_case(db: Session, case: CaseCreate, created_by: int):

    new_case = Case(
        case_id=generate_case_id(),
        title=case.title,
        description=case.description,
        investigator_id=case.investigator_id,
        priority=case.priority,
        status="Open",
        created_by=created_by
    )

    db.add(new_case)
    db.commit()
    db.refresh(new_case)

    return new_case