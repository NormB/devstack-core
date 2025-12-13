"""
DevStack Backup and Restore Module
===================================

Backup and restore operations with optional encryption support.

This module provides:
- Full and incremental backup creation
- Backup encryption using GPG
- Backup verification and integrity checking
- Restore operations with decryption

Functions:
- create_backup_manifest: Create manifest with checksums
- find_latest_full_backup: Find most recent full backup
- encrypt_file_gpg: Encrypt file with GPG
- decrypt_file_gpg: Decrypt GPG-encrypted file
- verify_backup_integrity: Verify backup using checksums
- setup_backup_passphrase: Interactive passphrase setup
- get_backup_passphrase: Retrieve stored passphrase
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional, Tuple, Any

from .utils import (
    console,
    calculate_file_checksum,
    VAULT_CONFIG_DIR
)


def create_backup_manifest(
    backup_dir: Path,
    backup_type: str = "full",
    base_backup: Optional[str] = None,
    previous_backup: Optional[str] = None,
    start_time: Optional[float] = None,
    encrypted: bool = False
) -> Dict[str, Any]:
    """
    Create a backup manifest file with metadata and checksums.

    Args:
        backup_dir: Path to backup directory
        backup_type: Type of backup ("full" or "incremental")
        base_backup: Base full backup ID for incremental backups
        previous_backup: Previous backup ID in incremental chain
        start_time: Backup start timestamp (for duration calculation)
        encrypted: Whether backup files are encrypted

    Returns:
        Manifest dictionary containing:
        - backup_id, timestamp, backup_type
        - database file info with checksums
        - encryption metadata if applicable
        - total size and duration
    """
    backup_id = backup_dir.name
    duration = time.time() - (start_time or time.time())

    manifest: Dict[str, Any] = {
        "backup_id": backup_id,
        "backup_type": backup_type,
        "timestamp": datetime.now().isoformat(),
        "base_backup": base_backup,
        "previous_backup": previous_backup,
        "encrypted": encrypted,
        "databases": {},
        "config": {},
        "total_size_bytes": 0,
        "duration_seconds": round(duration, 2),
        "vault_approle_used": True
    }

    if encrypted:
        manifest["encryption"] = {
            "algorithm": "AES256",
            "method": "GPG symmetric",
            "passphrase_hint": "vault-backup-passphrase"
        }

    # Database backup files
    db_files = {
        "postgres": "postgres_all.sql",
        "mysql": "mysql_all.sql",
        "mongodb": "mongodb_dump.archive",
        "forgejo": "forgejo_data.tar.gz"
    }

    for db_name, filename in db_files.items():
        file_path = backup_dir / filename
        encrypted_file_path = backup_dir / (filename + ".gpg")
        actual_file = encrypted_file_path if encrypted else file_path

        if actual_file.exists():
            file_size = actual_file.stat().st_size
            file_entry: Dict[str, Any] = {
                "type": backup_type if db_name == "forgejo" else "full",
                "file": actual_file.name,
                "size_bytes": file_size,
                "checksum": f"sha256:{calculate_file_checksum(actual_file)}"
            }

            if encrypted:
                file_entry["original_file"] = filename

            if db_name == "forgejo" and backup_type == "incremental" and base_backup:
                file_entry["base_backup"] = base_backup

            manifest["databases"][db_name] = file_entry
            manifest["total_size_bytes"] += file_size

    # Config file backup
    env_backup = backup_dir / ".env.backup"
    env_backup_encrypted = backup_dir / ".env.backup.gpg"
    actual_env = env_backup_encrypted if encrypted else env_backup

    if actual_env.exists():
        file_size = actual_env.stat().st_size
        config_entry: Dict[str, Any] = {
            "env_file": actual_env.name,
            "size_bytes": file_size,
            "checksum": f"sha256:{calculate_file_checksum(actual_env)}"
        }

        if encrypted:
            config_entry["original_file"] = ".env.backup"

        manifest["config"] = config_entry
        manifest["total_size_bytes"] += file_size

    # Write manifest
    manifest_file = backup_dir / "manifest.json"
    with open(manifest_file, 'w') as f:
        json.dump(manifest, f, indent=2)

    return manifest


def find_latest_full_backup(backups_dir: Optional[Path] = None) -> Optional[str]:
    """
    Find the most recent full backup directory.

    Args:
        backups_dir: Path to backups directory (default: ./backups)

    Returns:
        Backup directory name (e.g., "20251117_080000") or None if not found
    """
    if backups_dir is None:
        backups_dir = Path.cwd() / "backups"

    if not backups_dir.exists():
        return None

    for backup_dir in sorted(backups_dir.iterdir(), reverse=True):
        if not backup_dir.is_dir():
            continue

        manifest_file = backup_dir / "manifest.json"
        if manifest_file.exists():
            try:
                with open(manifest_file, 'r') as f:
                    manifest = json.load(f)
                    if manifest.get("backup_type") == "full":
                        return backup_dir.name
            except Exception:
                continue

    # Fallback: assume all backups are full if no manifests
    for backup_dir in sorted(backups_dir.iterdir(), reverse=True):
        if backup_dir.is_dir() and backup_dir.name[0].isdigit():
            return backup_dir.name

    return None


def setup_backup_passphrase() -> bool:
    """
    Interactive setup for backup encryption passphrase.

    Prompts user to create a passphrase and saves it to
    ~/.config/vault/backup-passphrase with 600 permissions.

    Returns:
        True if passphrase created successfully, False otherwise
    """
    import getpass

    passphrase_file = VAULT_CONFIG_DIR / "backup-passphrase"

    console.print("\n[cyan]═══ Backup Encryption Setup ═══[/cyan]\n")
    console.print("[yellow]No encryption passphrase found.[/yellow]")
    console.print("[cyan]Creating a passphrase will enable encrypted backups.[/cyan]\n")

    response = input("Create encryption passphrase? (y/n): ").strip().lower()
    if response != 'y':
        console.print("[yellow]Encryption setup cancelled.[/yellow]\n")
        return False

    while True:
        passphrase1 = getpass.getpass("Enter passphrase: ")
        if len(passphrase1) < 8:
            console.print("[red]Passphrase must be at least 8 characters.[/red]")
            continue

        passphrase2 = getpass.getpass("Confirm passphrase: ")
        if passphrase1 != passphrase2:
            console.print("[red]Passphrases do not match. Try again.[/red]")
            continue

        break

    try:
        passphrase_file.write_text(passphrase1)
        os.chmod(passphrase_file, 0o600)
        console.print(f"\n[green]✓ Passphrase saved:[/green] {passphrase_file}")
        console.print("[cyan]Permissions:[/cyan] 600 (owner read/write only)\n")
        return True
    except Exception as e:
        console.print(f"[red]Error saving passphrase: {e}[/red]\n")
        return False


def get_backup_passphrase(prompt_if_missing: bool = False) -> Optional[str]:
    """
    Retrieve backup encryption passphrase.

    Args:
        prompt_if_missing: If True, prompt user to create passphrase if not found

    Returns:
        Passphrase string or None if not available
    """
    passphrase_file = VAULT_CONFIG_DIR / "backup-passphrase"

    if passphrase_file.exists():
        try:
            return passphrase_file.read_text().strip()
        except Exception as e:
            console.print(f"[red]Error reading passphrase: {e}[/red]")
            return None

    if prompt_if_missing:
        if setup_backup_passphrase():
            return passphrase_file.read_text().strip()

    return None


def encrypt_file_gpg(file_path: Path, passphrase: str) -> bool:
    """
    Encrypt a file using GPG symmetric encryption (AES256).

    Args:
        file_path: Path to file to encrypt
        passphrase: Encryption passphrase

    Returns:
        True if encryption successful, False otherwise

    Notes:
        - Creates encrypted file with .gpg extension
        - Deletes original file after successful encryption
    """
    if not file_path.exists():
        console.print(f"[red]File not found: {file_path}[/red]")
        return False

    encrypted_path = Path(str(file_path) + ".gpg")

    try:
        result = subprocess.run(
            [
                "gpg",
                "--symmetric",
                "--cipher-algo", "AES256",
                "--batch",
                "--yes",
                "--passphrase", passphrase,
                "--output", str(encrypted_path),
                str(file_path)
            ],
            capture_output=True,
            check=False
        )

        if result.returncode != 0:
            error_msg = result.stderr.decode() if result.stderr else "Unknown error"
            console.print(f"[red]Encryption failed: {error_msg}[/red]")
            return False

        file_path.unlink()
        return True

    except Exception as e:
        console.print(f"[red]Encryption error: {e}[/red]")
        return False


def decrypt_file_gpg(
    encrypted_path: Path,
    passphrase: str,
    output_path: Optional[Path] = None
) -> bool:
    """
    Decrypt a GPG-encrypted file.

    Args:
        encrypted_path: Path to .gpg encrypted file
        passphrase: Decryption passphrase
        output_path: Optional output path (defaults to removing .gpg extension)

    Returns:
        True if decryption successful, False otherwise
    """
    if not encrypted_path.exists():
        console.print(f"[red]Encrypted file not found: {encrypted_path}[/red]")
        return False

    if output_path is None:
        output_path = Path(str(encrypted_path).removesuffix(".gpg"))

    try:
        result = subprocess.run(
            [
                "gpg",
                "--decrypt",
                "--batch",
                "--yes",
                "--passphrase", passphrase,
                "--output", str(output_path),
                str(encrypted_path)
            ],
            capture_output=True,
            check=False
        )

        if result.returncode != 0:
            error_msg = result.stderr.decode() if result.stderr else "Unknown error"
            console.print(f"[red]Decryption failed: {error_msg}[/red]")
            return False

        return True

    except Exception as e:
        console.print(f"[red]Decryption error: {e}[/red]")
        return False


def verify_backup_integrity(backup_dir: Path) -> Tuple[bool, Dict[str, Any]]:
    """
    Verify backup integrity using checksums from manifest.

    Args:
        backup_dir: Path to backup directory

    Returns:
        Tuple of (success, report) where:
        - success: True if all files verified
        - report: Dict with verification details:
            - files_verified: Number of files successfully verified
            - files_failed: Number of files that failed verification
            - files_total: Total number of files to verify
            - errors: List of error messages
            - warnings: List of warning messages
            - details: List of per-file verification results
    """
    report: Dict[str, Any] = {
        "files_verified": 0,
        "files_failed": 0,
        "files_total": 0,
        "errors": [],
        "warnings": [],
        "details": []
    }

    manifest_file = backup_dir / "manifest.json"
    if not manifest_file.exists():
        report["errors"].append("Manifest file not found")
        return False, report

    try:
        with open(manifest_file, 'r') as f:
            manifest = json.load(f)
    except json.JSONDecodeError as e:
        report["errors"].append(f"Manifest is corrupted: {e}")
        return False, report
    except Exception as e:
        report["errors"].append(f"Error reading manifest: {e}")
        return False, report

    # Validate manifest structure
    required_fields = ["backup_id", "backup_type", "encrypted", "databases"]
    for field in required_fields:
        if field not in manifest:
            report["errors"].append(f"Manifest missing required field: {field}")
            return False, report

    # Count total files
    report["files_total"] = len(manifest.get("databases", {}))
    if "config" in manifest and manifest["config"]:
        report["files_total"] += 1

    # Verify database files
    for db_name, db_info in manifest.get("databases", {}).items():
        filename = db_info.get("file")
        if not filename:
            report["errors"].append(f"{db_name}: Missing filename in manifest")
            report["files_failed"] += 1
            continue

        file_path = backup_dir / filename
        expected_checksum = db_info.get("checksum", "").replace("sha256:", "")

        if not file_path.exists():
            report["errors"].append(f"{filename}: File missing")
            report["files_failed"] += 1
            report["details"].append({
                "file": filename,
                "status": "missing",
                "size": 0
            })
            continue

        try:
            actual_checksum = calculate_file_checksum(file_path)
            file_size = file_path.stat().st_size

            if actual_checksum == expected_checksum:
                report["files_verified"] += 1
                report["details"].append({
                    "file": filename,
                    "status": "ok",
                    "size": file_size
                })
            else:
                report["files_failed"] += 1
                report["errors"].append(
                    f"{filename}: Checksum mismatch\n"
                    f"  Expected: {expected_checksum[:16]}...\n"
                    f"  Actual:   {actual_checksum[:16]}..."
                )
                report["details"].append({
                    "file": filename,
                    "status": "checksum_mismatch",
                    "size": file_size
                })
        except Exception as e:
            report["files_failed"] += 1
            report["errors"].append(f"{filename}: Verification error: {e}")
            report["details"].append({
                "file": filename,
                "status": "error",
                "size": 0
            })

    # Verify config file
    if "config" in manifest and manifest["config"]:
        config_info = manifest["config"]
        filename = config_info.get("env_file")
        if filename:
            file_path = backup_dir / filename
            expected_checksum = config_info.get("checksum", "").replace("sha256:", "")

            if not file_path.exists():
                report["errors"].append(f"{filename}: File missing")
                report["files_failed"] += 1
                report["details"].append({
                    "file": filename,
                    "status": "missing",
                    "size": 0
                })
            else:
                try:
                    actual_checksum = calculate_file_checksum(file_path)
                    file_size = file_path.stat().st_size

                    if actual_checksum == expected_checksum:
                        report["files_verified"] += 1
                        report["details"].append({
                            "file": filename,
                            "status": "ok",
                            "size": file_size
                        })
                    else:
                        report["files_failed"] += 1
                        report["errors"].append(
                            f"{filename}: Checksum mismatch\n"
                            f"  Expected: {expected_checksum[:16]}...\n"
                            f"  Actual:   {actual_checksum[:16]}..."
                        )
                        report["details"].append({
                            "file": filename,
                            "status": "checksum_mismatch",
                            "size": file_size
                        })
                except Exception as e:
                    report["files_failed"] += 1
                    report["errors"].append(f"{filename}: Verification error: {e}")
                    report["details"].append({
                        "file": filename,
                        "status": "error",
                        "size": 0
                    })

    success = (
        report["files_failed"] == 0 and
        report["files_verified"] == report["files_total"]
    )
    return success, report
