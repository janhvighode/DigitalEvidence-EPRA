"""
Custom exceptions for EPRA.
"""


class EPRAException(Exception):
    """Base EPRA Exception."""


class InvalidEvidenceException(EPRAException):
    """Raised when evidence object is invalid."""


class MissingMetadataException(EPRAException):
    """Raised when metadata is incomplete."""