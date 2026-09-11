import os
import requests
from dotenv import load_dotenv

load_dotenv()

BREVO_API_KEY = os.getenv("BREVO_API_KEY")
SENDER_EMAIL = os.getenv("SENDER_EMAIL")


def send_email(receiver_email: str, subject: str, body: str):

    url = "https://api.brevo.com/v3/smtp/email"

    headers = {
        "accept": "application/json",
        "api-key": BREVO_API_KEY,
        "content-type": "application/json"
    }

    data = {
        "sender": {
            "email": SENDER_EMAIL,
            "name": "Digital Evidence EPRA"
        },
        "to": [
            {
                "email": receiver_email
            }
        ],
        "subject": subject,
        "htmlContent": body
    }

    try:
        print(f"Sending email to: {receiver_email}")
        print(f"BREVO_API_KEY configured: {bool(BREVO_API_KEY)}")
        print(f"SENDER_EMAIL configured: {bool(SENDER_EMAIL)}")

        response = requests.post(
            url,
            headers=headers,
            json=data,
            timeout=20
        )

        print(f"Brevo response status: {response.status_code}")
        print(f"Brevo response: {response.text}")

        if response.status_code in [200, 201, 202]:
            print("Email sent successfully through Brevo")
            return True

        print("Brevo failed to send email")
        return False

    except Exception as e:
        print(f"EMAIL ERROR: {type(e).__name__}: {e}")
        return False