import os
import stat
import shutil
import zipfile
from pathlib import Path
from uuid import uuid4
from dataclasses import dataclass
from typing import List, Tuple
from fastapi import HTTPException, status


# Configurable Forensic Safe Limits
MAX_ARCHIVE_SIZE_BYTES = 100 * 1024 * 1024       # 100 MB
MAX_UNCOMPRESSED_TOTAL_BYTES = 250 * 1024 * 1024 # 250 MB
MAX_SINGLE_FILE_BYTES = 50 * 1024 * 1024         # 50 MB
MAX_FILE_COUNT = 100                             # Max 100 files
MIN_FILE_COUNT = 1                               # At least 1 file
MAX_COMPRESSION_RATIO = 100.0                    # 100:1 bomb threshold
MIN_BOMB_CHECK_SIZE = 512 * 1024                 # Apply ratio check above 512 KB uncompressed


@dataclass
class SafeArchiveMember:
    relative_path: str
    safe_name: str
    staged_path: Path
    file_size: int


class ZipSecurityValidator:
    """
    Forensic security validator and safe extractor for ZIP evidence archives.
    Protects against Zip Slip, zip bombs, symlink attacks, path traversals,
    and denial of service.
    """

    @staticmethod
    def validate_and_stage_zip(
        archive_path: Path,
        staging_root: Path
    ) -> Tuple[List[SafeArchiveMember], Path]:
        """
        Thoroughly validates archive integrity and member safety.
        Safely extracts genuine leaf files into an isolated staging sandbox.
        Returns list of SafeArchiveMember objects and the staging directory path.
        """
        # 1. Verify file exists
        if not archive_path.is_file():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Uploaded archive file could not be read."
            )

        # 2. Verify archive file size <= 100 MB
        archive_size = archive_path.stat().st_size
        if archive_size > MAX_ARCHIVE_SIZE_BYTES:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Archive size exceeds maximum permitted limit of {MAX_ARCHIVE_SIZE_BYTES // (1024 * 1024)} MB."
            )

        # 3. Verify magic bytes / valid ZIP structure
        if not zipfile.is_zipfile(archive_path):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid ZIP archive: file is corrupted or not a recognized ZIP format."
            )

        staging_dir = staging_root / f"staging_{uuid4().hex}"
        staging_dir.mkdir(parents=True, exist_ok=True)

        try:
            with zipfile.ZipFile(archive_path, "r") as zf:
                infolist = zf.infolist()

                # Filter out directory entries
                file_members = [
                    zinfo for zinfo in infolist
                    if not zinfo.is_dir() and not zinfo.filename.endswith(("/", "\\"))
                ]

                # 4. File count limits (1 - 100 files)
                if len(file_members) < MIN_FILE_COUNT:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="ZIP archive is empty: contains no valid evidence files."
                    )

                if len(file_members) > MAX_FILE_COUNT:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"ZIP archive exceeds maximum limit of {MAX_FILE_COUNT} files (found {len(file_members)})."
                    )

                # 5. Member inspections before extraction
                total_uncompressed = 0
                for zinfo in file_members:
                    raw_name = zinfo.filename.strip()

                    # 5a. Encrypted / password protected
                    if bool(zinfo.flag_bits & 0x1):
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Encrypted or password-protected archives are not supported for automated ingestion (member: '{raw_name}')."
                        )

                    # 5b. Symlink / special member check
                    mode = zinfo.external_attr >> 16
                    if stat.S_ISLNK(mode) or stat.S_ISFIFO(mode) or stat.S_ISSOCK(mode):
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Unsafe archive member: symlinks, pipes, and socket entries are prohibited (member: '{raw_name}')."
                        )

                    # 5c. Size limits
                    if zinfo.file_size > MAX_SINGLE_FILE_BYTES:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Archive member '{raw_name}' exceeds maximum individual file size limit of {MAX_SINGLE_FILE_BYTES // (1024 * 1024)} MB."
                        )

                    total_uncompressed += zinfo.file_size
                    if total_uncompressed > MAX_UNCOMPRESSED_TOTAL_BYTES:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Cumulative uncompressed archive size exceeds maximum limit of {MAX_UNCOMPRESSED_TOTAL_BYTES // (1024 * 1024)} MB."
                        )

                    # 5d. Compression ratio check (ZIP bomb prevention)
                    if zinfo.compress_size > 0 and zinfo.file_size > MIN_BOMB_CHECK_SIZE:
                        ratio = zinfo.file_size / zinfo.compress_size
                        if ratio > MAX_COMPRESSION_RATIO:
                            raise HTTPException(
                                status_code=status.HTTP_400_BAD_REQUEST,
                                detail=f"Suspicious compression ratio ({ratio:.1f}:1) detected for member '{raw_name}'. Potential decompression bomb rejected."
                            )

                    # 5e. Path traversal / Zip Slip checks
                    # Reject leading slashes, backslashes, drive letters
                    if raw_name.startswith(("/", "\\")):
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Security violation: absolute paths are prohibited in archive (member: '{raw_name}')."
                        )

                    # Reject Windows drive letters (e.g. C: or C:/)
                    if len(raw_name) >= 2 and raw_name[1] == ":":
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Security violation: Windows drive letters are prohibited in archive (member: '{raw_name}')."
                        )

                    p = Path(raw_name)
                    if ".." in p.parts:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Security violation: directory traversal '..' detected in member '{raw_name}'."
                        )

                # 6. Archive CRC integrity test
                corrupted_member = zf.testzip()
                if corrupted_member is not None:
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail=f"ZIP archive integrity check failed: member '{corrupted_member}' is corrupted."
                    )

                # 7. Safe extraction to staging sandbox
                resolved_staging = staging_dir.resolve()
                extracted_members: List[SafeArchiveMember] = []

                for zinfo in file_members:
                    raw_name = zinfo.filename.replace("\\", "/").strip()
                    parts = [pt for pt in raw_name.split("/") if pt and pt != "."]
                    safe_rel_path = "/".join(parts)
                    leaf_name = parts[-1] if parts else "evidence_file"

                    # Calculate target destination inside staging
                    target_dest = (staging_dir / safe_rel_path).resolve()

                    # Guarantee target does not escape staging root
                    try:
                        target_dest.relative_to(resolved_staging)
                    except ValueError:
                        raise HTTPException(
                            status_code=status.HTTP_400_BAD_REQUEST,
                            detail=f"Security violation: extracted path for '{raw_name}' escapes staging directory."
                        )

                    target_dest.parent.mkdir(parents=True, exist_ok=True)

                    # Stream member to disk (do not use blind extractall)
                    with zf.open(zinfo, "r") as source_fp, open(target_dest, "wb") as dest_fp:
                        shutil.copyfileobj(source_fp, dest_fp)

                    extracted_members.append(
                        SafeArchiveMember(
                            relative_path=safe_rel_path,
                            safe_name=leaf_name,
                            staged_path=target_dest,
                            file_size=target_dest.stat().st_size
                        )
                    )

                return extracted_members, staging_dir

        except HTTPException:
            # Clean up staging sandbox on any validation failure
            shutil.rmtree(staging_dir, ignore_errors=True)
            raise
        except Exception as exc:
            shutil.rmtree(staging_dir, ignore_errors=True)
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Archive validation failed: {str(exc)}"
            )

    @staticmethod
    def cleanup_staging(staging_dir: Path):
        """Safely removes temporary staging sandbox directory."""
        if staging_dir and staging_dir.exists():
            shutil.rmtree(staging_dir, ignore_errors=True)
