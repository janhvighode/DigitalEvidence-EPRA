def registration_approved_template(
    full_name: str,
    username: str,
    temporary_password: str
):

    return f"""
Dear {full_name},

Congratulations!

Your registration request for the Smart Digital Evidence Prioritization System has been approved.

Your login credentials are:

Username: {username}
Temporary Password: {temporary_password}

For security reasons, you must change your password after your first login.

Thank you.

Regards,
Administrator
"""


def forgot_password_otp_template(
    full_name: str,
    otp: str
):

    return f"""
Dear {full_name},

We received a request to reset your password.

Your One-Time Password (OTP) is:

{otp}

This OTP is valid for 10 minutes.

If you did not request this password reset, please ignore this email.

Regards,
Administrator
"""


def password_changed_template(
    full_name: str
):

    return f"""
Dear {full_name},

Your password has been changed successfully.

If you did not perform this action, please contact the Administrator immediately.

Regards,
Administrator
"""