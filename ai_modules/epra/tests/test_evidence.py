from ai_modules.epra.models.evidence import Evidence

def test_create_evidence():
    evidence = Evidence(
        evidence_id="EV001",
        case_id="CASE001",
        file_name="crime_scene.jpg",
        file_extension="jpg",
        file_type="IMAGE",
        mime_type="image/jpeg",
        file_size=2048576,
        file_path="uploads/crime_scene.jpg"
    )

    assert evidence.evidence_id == "EV001"
    assert evidence.file_type == "IMAGE"