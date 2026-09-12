"""
Cryptographic Format Validator for Member 5.

Validates whether string digests conform to 64-hex SHA-256 formatting.
Notice: In accordance with confirmed ownership boundaries, Member 5 does NOT
generate or recalculate SHA-256 hashes for evidence files.
All evidence hashes are generated and verified exclusively by the integrated backend.
"""
import re

EMPTY_FILE_SHA256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
SHA256_REGEX = re.compile(r"^[0-9a-fA-F]{64}$")


class FileHashService:

    @staticmethod
    def is_valid_sha256(hash_str: str) -> bool:
        """
        Validate whether a string is a well-formed 64-character hex SHA-256 digest.
        Does NOT compute or generate any hashes.
        """
        if not hash_str or not isinstance(hash_str, str):
            return False
        return bool(SHA256_REGEX.match(hash_str.strip()))