import tempfile
from pathlib import Path

from ai_modules.epra.intelligence.metadata_extractor import MetadataExtractor


def test_metadata_extraction():

    extractor = MetadataExtractor()

    with tempfile.NamedTemporaryFile(suffix=".jpg", delete=False) as temp_file:

        temp_file.write(b"EPRA Test File")

        temp_path = temp_file.name

    metadata = extractor.extract(temp_path)

    assert metadata["file_name"] == Path(temp_path).name
    assert metadata["extension"] == ".jpg"
    assert metadata["size_bytes"] > 0
    assert "created_time" in metadata
    assert "modified_time" in metadata


def test_metadata_keys():

    extractor = MetadataExtractor()

    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as temp_file:

        temp_file.write(b"PDF Test")

        temp_path = temp_file.name

    metadata = extractor.extract(temp_path)

    expected_keys = {
        "file_name",
        "extension",
        "size_bytes",
        "created_time",
        "modified_time"
    }

    assert set(metadata.keys()) == expected_keys