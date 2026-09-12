"""
Mock End-to-End Smoke Check Script for Member 5 Subsystem.
NOTE: This script runs an end-to-end verification against an isolated MockBackendProvider test harness.
It does NOT claim or execute a live connection to an unverified shared backend.
Database and storage are strictly isolated to temporary directories during execution.

Simulates an investigator workflow:
1. Check API root & health
2. Register case and evidence in MockBackendProvider (simulating backend evidence contracts)
3. Fetch metadata summary cards & searchable table
4. Inspect selected evidence file details (Pillow dimensions/mode)
5. View evidence custody summary & custody timeline
6. Initiate custody transfer (PENDING_RECEIPT) and confirm receipt (COMPLETED)
7. Audit-edit current custody location/department
8. Generate draft preview report (without database registration)
9. Generate formal PDF forensic report (persisting snapshot & audit logs)
10. Safely download report by report_id
11. Generate and download JSON hash manifest (without re-upload or recalculation)
12. Export downstream EPRA contract
"""
import os
import sys
import shutil
import tempfile
from pathlib import Path

# Configure isolated DB/storage BEFORE app import to protect production DB and uploads
_SMOKE_TMP_DIR = Path(tempfile.mkdtemp(prefix="member5_smoke_check_"))
os.environ["EVIDENCE_DB_URL"] = f"sqlite:///{(_SMOKE_TMP_DIR / 'smoke_vault.db').as_posix()}"
os.environ["EVIDENCE_STORAGE_DIR"] = str(_SMOKE_TMP_DIR / "uploads")

backend_dir = str(Path(__file__).resolve().parent.parent)
if backend_dir not in sys.path:
    sys.path.insert(0, backend_dir)

from fastapi.testclient import TestClient
from app.hash_api import app
from app.services.backend_adapter import (
    set_backend_adapter,
    SharedBackendAdapter,
    MockBackendProvider,
    CaseData,
    EvidenceItem
)

client = TestClient(app)


def smoke_check():
    print("=" * 80)
    print("MEMBER 5 SECURITY & REPORTING - ISOLATED MOCK BACKEND SMOKE CHECK")
    print("(Isolated test harness with MockBackendProvider - NOT live shared backend)")
    print("=" * 80)

    try:
        # 1. Health / Root
        print("\n[Step 1] Checking API Root...")
        root_res = client.get("/")
        assert root_res.status_code == 200, root_res.text
        print("  -> Status: OK |", root_res.json()["module"])

        # 2. Setup external case in mock provider
        print("\n[Step 2] Configuring MockBackendProvider with Case & Evidence...")
        mock_provider = MockBackendProvider()
        set_backend_adapter(mock_provider)

        case_id = "CASE-2025-047"
        mock_provider.register_case(CaseData(
            case_id=case_id,
            case_title="Cyber Fraud Investigation",
            crime_type="Financial Fraud",
            investigator_name="Jane Doe",
            investigator_role="Cyber Expert",
            department="Cyber Cell, Mumbai"
        ))

        # Existing evidence item with backend-supplied hash
        ev_content = b"CRITICAL FORENSIC TRANSACTION EVIDENCE"
        mock_provider.register_evidence(
            EvidenceItem(
            evidence_id="EV-101",
            case_id=case_id,
            original_filename="transaction_screenshot.png",
            file_type="PNG Image",
            file_size_bytes=len(ev_content),
            original_sha256="a3f5e8d9c7b2e4f1a6c9d3e8b7f5a2c4d8e9f7b6c5d4a3e2f1b0c9d8e7f6a5b4",
            current_sha256="a3f5e8d9c7b2e4f1a6c9d3e8b7f5a2c4d8e9f7b6c5d4a3e2f1b0c9d8e7f6a5b4",
            verification_status="Verified",
            verification_source="Integrated Backend SHA-256 Verifier"
        ),
        file_bytes=ev_content
    )
        print(f"  -> Evidence EV-101 registered with backend hash.")

        # 3. Metadata Extraction Summary & Table
        print("\n[Step 3] Fetching Case Metadata Summary & Table...")
        sum_res = client.get(f"/evidence/case/{case_id}/summary")
        assert sum_res.status_code == 200, sum_res.text
        print(f"  -> Summary: {sum_res.json()['total_files']} files, {sum_res.json()['total_size_formatted']}")

        table_res = client.get(f"/evidence/case/{case_id}/metadata")
        assert table_res.status_code == 200, table_res.text
        table_data = table_res.json()
        print(f"  -> Table: {table_data['total_items']} items returned. First: {table_data['items'][0]['original_filename']}")

        # 4. Selected File Details
        print("\n[Step 4] Inspecting Selected File Details (EV-101)...")
        details_res = client.get("/evidence/EV-101/details")
        assert details_res.status_code == 200, details_res.text
        det = details_res.json()
        print(f"  -> Filename: {det['filename']} | Hash Status: {det['hash_information']['verification_status']}")

        # 5. Custody Summary & Timeline
        print("\n[Step 5] Checking Custody Summary & Timeline for EV-101...")
        c_sum = client.get("/evidence/EV-101/custody/summary")
        assert c_sum.status_code == 200, c_sum.text
        print(f"  -> Total Events: {c_sum.json()['total_events']} | Handlers: {c_sum.json()['handlers_count']}")

        # 6. Custody Transfer Workflow (No local hashing)
        print("\n[Step 6] Initiating Transfer of EV-101...")
        trf_init = client.post(
            "/evidence/transfer/initiate",
            json={
                "evidence_id": "EV-101",
                "sender_name": "Inspector Rahul Singh",
                "sender_role": "Investigator",
                "recipient_name": "Jane Doe",
                "recipient_role": "Cyber Expert",
                "reason_or_remarks": "Assigned for forensic analysis"
            }
        )
        assert trf_init.status_code == 200, trf_init.text
        trf_ref = trf_init.json()["transfer_reference"]
        print(f"  -> Transfer initiated. Ref: {trf_ref} [Status: {trf_init.json()['status']}]")

        print("\n[Step 7] Confirming Transfer Receipt by Jane Doe...")
        trf_recv = client.post(
            f"/evidence/transfer/receive?transfer_reference={trf_ref}",
            json={
                "recipient_name": "Jane Doe",
                "recipient_role": "Cyber Expert",
                "department": "Cyber Cell, Mumbai",
                "location": "Digital Evidence Lab",
                "remarks": "Received in sealed container."
            }
        )
        assert trf_recv.status_code == 200, trf_recv.text
        print(f"  -> Transfer confirmed! Status: {trf_recv.json()['status']}")

        # 7. Audited Current Custody Update
        print("\n[Step 8] Audited Edit of Current Custody Location...")
        edit_res = client.put(
            "/evidence/EV-101/custody/current",
            json={
                "department": "Cyber Cell, Mumbai",
                "location": "Secure Storage Vault B",
                "remarks": "Secured in biometric evidence safe",
                "actor_name": "Jane Doe"
            }
        )
        assert edit_res.status_code == 200, edit_res.text
        print(f"  -> New Location: {edit_res.json()['location']}")

        # 8. Draft Report Preview
        print("\n[Step 9] Generating Draft Report Preview...")
        prev_res = client.post(
            "/report/preview",
            json={
                "case_id": case_id,
                "case_title": "Cyber Fraud Investigation",
                "report_type": "Comprehensive Forensic Report",
                "investigator_name": "Jane Doe"
            }
        )
        assert prev_res.status_code == 200, prev_res.text
        assert prev_res.headers["content-type"] == "application/pdf"
        print(f"  -> Preview generated: {len(prev_res.content)} bytes.")

        # 9. Final Report Generation
        print("\n[Step 10] Generating Final Comprehensive Forensic Report...")
        gen_res = client.post(
            "/report/generate",
            json={
                "case_id": case_id,
                "case_title": "Cyber Fraud Investigation",
                "report_type": "Comprehensive Forensic Report",
                "investigator_name": "Jane Doe",
                "investigator_role": "Cyber Expert",
                "conclusions_text": "Cryptographic baseline integrity verified by integrated backend.",
                "recommendations_text": "Proceed to evidence admission."
            }
        )
        assert gen_res.status_code == 200, gen_res.text
        rep_data = gen_res.json()
        rep_id = rep_data["report_id"]
        print(f"  -> Final report #{rep_id} generated. Size: {rep_data['file_size_formatted']}")

        # 10. Controlled Report Download
        print(f"\n[Step 11] Downloading Report #{rep_id}...")
        dl_res = client.get(f"/report/download/{rep_id}")
        assert dl_res.status_code == 200, dl_res.text
        assert dl_res.headers["content-type"] == "application/pdf"
        print(f"  -> Download successful: {len(dl_res.content)} bytes.")

        # 11. Hash Manifest Generation
        print("\n[Step 12] Exporting JSON Hash Manifest...")
        man_res = client.post("/hash/generate-manifest", data={"case_id": case_id})
        assert man_res.status_code == 200, man_res.text
        man_data = man_res.json()
        print(f"  -> Manifest generated: {man_data['total_evidence_files']} files, Missing: {man_data['missing_hashes_count']}")

        # 12. Downstream EPRA Contract
        print("\n[Step 13] Fetching Downstream EPRA Contract...")
        epra_res = client.get(f"/downstream/epra/{case_id}")
        assert epra_res.status_code == 200, epra_res.text
        epra_data = epra_res.json()
        print(f"  -> Contract Version: {epra_data['contract_version']} | Total Items: {epra_data['total_evidence_count']}")

        print("\n" + "=" * 80)
        print("ALL MEMBER 5 SMOKE CHECK STEPS COMPLETED SUCCESSFULLY!")
        print("=" * 80)
    finally:
        set_backend_adapter(SharedBackendAdapter())
        if _SMOKE_TMP_DIR.exists():
            shutil.rmtree(_SMOKE_TMP_DIR, ignore_errors=True)


if __name__ == "__main__":
    smoke_check()
