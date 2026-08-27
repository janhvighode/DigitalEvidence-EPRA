import random
import string


def generate_temporary_password(length=12):

    uppercase = string.ascii_uppercase
    lowercase = string.ascii_lowercase
    digits = string.digits
    special = "!@#$%^&*"

    password = [
        random.choice(uppercase),
        random.choice(lowercase),
        random.choice(digits),
        random.choice(special)
    ]

    all_characters = uppercase + lowercase + digits + special

    password += random.choices(
        all_characters,
        k=length - 4
    )

    random.shuffle(password)

    return "".join(password)