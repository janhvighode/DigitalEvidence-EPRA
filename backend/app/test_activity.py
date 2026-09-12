import sys
from pathlib import Path
backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

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

    # Assertions
    assert len(logs) == len(events), "Log count must equal events count"
    assert all(log["investigator"] == investigator_name for log in logs), "Investigator name must match"
    assert all("unverified" in log["time"].lower() or "not recorded" in log["time"].lower() for log in logs), (
        "Supplied demo strings must be clearly labeled as unverified, avoiding false 'now' timestamps"
    )

    print("\n" + "=" * 60)
    print("ACTIVITY LOGGING TEST SUCCESS (ASSERTIONS PASSED)")
    print("=" * 60)


if __name__ == "__main__":
    run_test()