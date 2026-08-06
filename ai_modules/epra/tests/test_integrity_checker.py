import tempfile

from ai_modules.epra.intelligence.integrity_checker import IntegrityChecker


def test_hash_generation():

    checker = IntegrityChecker()

    with tempfile.NamedTemporaryFile(delete=False) as temp_file:

        temp_file.write(b"EPRA Integrity Test")

        temp_path = temp_file.name

    file_hash = checker.generate_hash(temp_path)

    assert isinstance(file_hash, str)
    assert len(file_hash) == 64


def test_integrity_verification():

    checker = IntegrityChecker()

    with tempfile.NamedTemporaryFile(delete=False) as temp_file:

        temp_file.write(b"Evidence File")

        temp_path = temp_file.name

    original_hash = checker.generate_hash(temp_path)

    assert checker.verify_integrity(temp_path, original_hash)


def test_integrity_failure():

    checker = IntegrityChecker()

    with tempfile.NamedTemporaryFile(delete=False) as temp_file:

        temp_file.write(b"Evidence File")

        temp_path = temp_file.name

    fake_hash = "0" * 64

    assert not checker.verify_integrity(temp_path, fake_hash)