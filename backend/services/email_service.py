import os
from dotenv import load_dotenv

load_dotenv()

import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587

SENDER_EMAIL = os.getenv("SENDER_EMAIL")
SENDER_PASSWORD = os.getenv("SENDER_PASSWORD")


def send_email(
    receiver_email: str,
    subject: str,
    body: str
):

    message = MIMEMultipart()

    message["From"] = SENDER_EMAIL
    message["To"] = receiver_email
    message["Subject"] = subject

    message.attach(
        MIMEText(body, "html")
    )

    try:
        # DEBUGGING
        print(f"Attempting to send email to: {receiver_email}")
        print(f"SENDER_EMAIL configured: {bool(SENDER_EMAIL)}")
        print(f"SENDER_PASSWORD configured: {bool(SENDER_PASSWORD)}")
        print(f"Trying to connect to {SMTP_SERVER}:{SMTP_PORT}...")

        server = smtplib.SMTP(
        SMTP_SERVER,
        SMTP_PORT,
        timeout=20
        )

        print("SMTP connection successful")

        server.starttls()

        print("Connecting to Gmail SMTP...")

        server.login(
            SENDER_EMAIL,
            SENDER_PASSWORD
        )

        print("Gmail login successful")

        server.sendmail(
            SENDER_EMAIL,
            receiver_email,
            message.as_string()
        )

        server.quit()

        print("Email sent successfully")
        return True

    except Exception as e:
        print(f"EMAIL ERROR: {type(e).__name__}: {e}")
        return False