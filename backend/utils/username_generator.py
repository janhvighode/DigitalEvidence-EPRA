import re
from sqlalchemy.orm import Session

from models.user import User


def generate_unique_username(
    db: Session,
    full_name: str,
    branch_name: str
):

    name = full_name.split()[0].lower()
    name = re.sub(r'[^a-z0-9]', '', name)

    # Take only the first word of the branch/city name
    branch = branch_name.lower()

    branch = branch.replace(" cyber cell", "")

    branch = branch.replace(" ", "")

    branch = re.sub(r'[^a-z0-9]', '', branch)

    username = f"{name}{branch}"

    original_username = username

    counter = 1

    while db.query(User).filter(
        User.username == username
    ).first():

        username = f"{original_username}{counter}"

        counter += 1

    return username