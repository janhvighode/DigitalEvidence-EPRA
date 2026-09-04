from app.services.activity_service import ActivityService


def run_test():

    investigator_name = "Deepak Sharma"

    events = [
        "Evidence Uploaded",
        "SHA-256 Hash Generated",
        "Evidence Integrity Verified",
        "Tamper Detection Performed",
        "Investigation Report Generated"
    ]

    logs = ActivityService.generate_activity_log(
        investigator_name,
        events
    )

    print("=" * 60)
    print("ACTIVITY LOGGING TEST")
    print("=" * 60)

    for index, log in enumerate(logs, start=1):

        print(f"\nActivity {index}")
        print("Investigator :", log["investigator"])
        print("Activity     :", log["activity"])
        print("Time         :", log["time"])

    if len(logs) == len(events):

        print("\n" + "=" * 60)
        print("ACTIVITY LOGGING TEST SUCCESS")
        print("=" * 60)

    else:

        print("\nACTIVITY LOGGING TEST FAILED")


if __name__ == "__main__":
    run_test()