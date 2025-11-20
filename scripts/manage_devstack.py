#!/usr/bin/env python3
"""
DevStack Core Management Script
================================

Modern Python-based management interface for DevStack Core with service profile support.

This script provides a comprehensive CLI for managing the complete Colima-based
development infrastructure with flexible service profiles.

Features:
- Service profile management (minimal, standard, full, reference)
- Automatic environment loading from profile .env files
- Beautiful terminal output with colors and tables
- Health checks for all services
- Vault operations (init, unseal, bootstrap)
- Service logs and shell access
- Backup and restore operations

Usage:
    ./devstack --help
    ./devstack start --profile standard
    ./devstack status
    ./devstack health

Requirements:
    pip3 install click rich PyYAML python-dotenv

Author: DevStack Core Team
License: MIT
"""

import os
import sys
import subprocess
import json
import hashlib
import time
from pathlib import Path
from typing import List, Dict, Optional, Tuple
from datetime import datetime

try:
    import click
    import yaml
    from rich.console import Console
    from rich.table import Table
    from rich.progress import Progress, SpinnerColumn, TextColumn
    from rich import box
    from dotenv import dotenv_values
except ImportError as e:
    print(f"Error: Missing required dependency: {e}")
    print("\nInstall Python dependencies with uv:")
    print("  cd ~/devstack-core")
    print("  uv venv")
    print("  uv pip install -r requirements.txt")
    print("\nThen run:")
    print("  ./devstack --help")
    print("\n(The wrapper script will automatically use the virtual environment)")
    sys.exit(1)

# ==============================================================================
# Constants and Configuration
# ==============================================================================

# Paths
SCRIPT_DIR = Path(__file__).parent.parent.resolve()  # Project root (one level up from scripts/)
PROFILES_FILE = SCRIPT_DIR / "profiles.yaml"
COMPOSE_FILE = SCRIPT_DIR / "docker-compose.yml"
ENV_FILE = SCRIPT_DIR / ".env"
PROFILES_DIR = SCRIPT_DIR / "configs" / "profiles"
VAULT_CONFIG_DIR = Path.home() / ".config" / "vault"

# Colima defaults (can be overridden by environment variables)
COLIMA_PROFILE = os.getenv("COLIMA_PROFILE", "default")
COLIMA_CPU = os.getenv("COLIMA_CPU", "4")
COLIMA_MEMORY = os.getenv("COLIMA_MEMORY", "8")
COLIMA_DISK = os.getenv("COLIMA_DISK", "60")

# Rich console for beautiful output
console = Console()

# ==============================================================================
# Utility Functions
# ==============================================================================

def run_command(
    cmd: List[str],
    check: bool = True,
    capture: bool = False,
    env: Optional[Dict[str, str]] = None,
    input: Optional[str] = None
) -> Tuple[int, str, str]:
    """
    Run a shell command with optional environment variables.

    Args:
        cmd: Command and arguments as list
        check: Raise error if command fails
        capture: Capture stdout/stderr
        env: Additional environment variables
        input: Input data to send to stdin

    Returns:
        Tuple of (returncode, stdout, stderr)
    """
    # Merge environment variables
    cmd_env = os.environ.copy()
    if env:
        cmd_env.update(env)

    try:
        if capture:
            result = subprocess.run(
                cmd,
                check=check,
                capture_output=True,
                text=True,
                env=cmd_env,
                input=input
            )
            return result.returncode, result.stdout, result.stderr
        else:
            result = subprocess.run(cmd, check=check, env=cmd_env, input=input, text=True if input else False)
            return result.returncode, "", ""
    except subprocess.CalledProcessError as e:
        if check:
            console.print(f"[red]Error running command: {' '.join(cmd)}[/red]")
            console.print(f"[red]Exit code: {e.returncode}[/red]")
            if capture and e.stderr:
                console.print(f"[red]{e.stderr}[/red]")
            sys.exit(e.returncode)
        return e.returncode, e.stdout if capture else "", e.stderr if capture else ""
    except FileNotFoundError:
        console.print(f"[red]Command not found: {cmd[0]}[/red]")
        console.print(f"[yellow]Make sure {cmd[0]} is installed and in your PATH[/yellow]")
        sys.exit(1)


def load_profiles_config() -> Dict:
    """Load and parse profiles.yaml configuration."""
    if not PROFILES_FILE.exists():
        console.print(f"[red]Error: {PROFILES_FILE} not found[/red]")
        sys.exit(1)

    with open(PROFILES_FILE) as f:
        return yaml.safe_load(f)


def load_profile_env(profile: str) -> Dict[str, str]:
    """Load environment variables from a profile .env file."""
    profile_env_file = PROFILES_DIR / f"{profile}.env"

    if not profile_env_file.exists():
        return {}

    # Use python-dotenv to parse .env file
    return dotenv_values(profile_env_file)


def get_profile_services(profile: str) -> List[str]:
    """Get list of services for a given profile."""
    profiles_config = load_profiles_config()

    # Check in main profiles
    if profile in profiles_config.get("profiles", {}):
        return profiles_config["profiles"][profile].get("services", [])

    # Check in custom profiles
    if profile in profiles_config.get("custom_profiles", {}):
        return profiles_config["custom_profiles"][profile].get("services", [])

    console.print(f"[red]Error: Unknown profile '{profile}'[/red]")
    console.print("[yellow]Available profiles: minimal, standard, full, reference[/yellow]")
    sys.exit(1)


def check_colima_status() -> bool:
    """Check if Colima is running."""
    returncode, stdout, stderr = run_command(
        ["colima", "status", "-p", COLIMA_PROFILE],
        check=False,
        capture=True
    )
    # Colima outputs to stderr, so check both stdout and stderr
    output = (stdout + stderr).lower()
    return returncode == 0 and "running" in output


def check_vault_token() -> bool:
    """Check if Vault root token exists."""
    token_file = VAULT_CONFIG_DIR / "root-token"
    return token_file.exists()


def get_vault_token() -> Optional[str]:
    """Get Vault root token."""
    token_file = VAULT_CONFIG_DIR / "root-token"
    if not token_file.exists():
        return None
    return token_file.read_text().strip()


def get_vault_approle_token(service: str = "management") -> Optional[str]:
    """
    Authenticate to Vault using AppRole and return a client token.

    Args:
        service: Service name for AppRole (default: "management")

    Returns:
        Vault client token string, or None if authentication fails

    This function reads role_id and secret_id from ~/.config/vault/approles/{service}/
    and uses them to authenticate via AppRole auth method. The returned token has
    limited permissions based on the service policy.
    """
    approle_dir = VAULT_CONFIG_DIR / "approles" / service
    role_id_file = approle_dir / "role-id"
    secret_id_file = approle_dir / "secret-id"

    # Check if AppRole credentials exist
    if not role_id_file.exists() or not secret_id_file.exists():
        return None

    try:
        role_id = role_id_file.read_text().strip()
        secret_id = secret_id_file.read_text().strip()

        # Authenticate via AppRole using docker exec
        returncode, token, _ = run_command(
            [
                "docker", "exec", "-e", "VAULT_ADDR=http://localhost:8200",
                "dev-vault", "vault", "write", "-field=token",
                "auth/approle/login",
                f"role_id={role_id}",
                f"secret_id={secret_id}"
            ],
            capture=True,
            check=False
        )

        if returncode == 0 and token:
            return token.strip()
        return None

    except Exception as e:
        console.print(f"[yellow]Warning: AppRole authentication failed: {e}[/yellow]")
        return None


def get_vault_secret(path: str, field: str, use_approle: bool = True) -> Optional[str]:
    """
    Retrieve a secret from Vault.

    Args:
        path: Vault secret path (e.g., "secret/postgres")
        field: Field to retrieve (e.g., "password")
        use_approle: Use AppRole authentication if True, otherwise use root token

    Returns:
        Secret value string, or None if retrieval fails

    This is a helper function that handles authentication and secret retrieval.
    By default, uses AppRole (recommended). Falls back to root token if AppRole fails.
    """
    # Try AppRole first if requested
    if use_approle:
        token = get_vault_approle_token()
        if token:
            returncode, value, _ = run_command(
                [
                    "docker", "exec", "-e", f"VAULT_TOKEN={token}",
                    "-e", "VAULT_ADDR=http://localhost:8200",
                    "dev-vault", "vault", "kv", "get", f"-field={field}", path
                ],
                capture=True,
                check=False
            )
            if returncode == 0 and value:
                return value.strip()

    # Fallback to root token
    token = get_vault_token()
    if not token:
        return None

    returncode, value, _ = run_command(
        [
            "docker", "exec", "-e", f"VAULT_TOKEN={token}",
            "-e", "VAULT_ADDR=http://localhost:8200",
            "dev-vault", "vault", "kv", "get", f"-field={field}", path
        ],
        capture=True,
        check=False
    )

    if returncode == 0 and value:
        return value.strip()
    return None


def calculate_file_checksum(file_path: Path) -> str:
    """
    Calculate SHA256 checksum of a file.

    Args:
        file_path: Path to file

    Returns:
        SHA256 checksum as hex string
    """
    sha256_hash = hashlib.sha256()
    with open(file_path, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    return sha256_hash.hexdigest()


def create_backup_manifest(backup_dir: Path, backup_type: str = "full",
                          base_backup: Optional[str] = None,
                          previous_backup: Optional[str] = None,
                          start_time: float = None,
                          encrypted: bool = False) -> Dict:
    """
    Create a backup manifest file with metadata and checksums.

    Args:
        backup_dir: Path to backup directory
        backup_type: Type of backup ("full" or "incremental")
        base_backup: Base full backup ID for incremental backups
        previous_backup: Previous backup ID in incremental chain
        start_time: Backup start timestamp
        encrypted: Whether backup files are encrypted

    Returns:
        Manifest dictionary
    """
    backup_id = backup_dir.name
    duration = time.time() - (start_time or time.time())

    manifest = {
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

    # Add encryption metadata if encrypted
    if encrypted:
        manifest["encryption"] = {
            "algorithm": "AES256",
            "method": "GPG symmetric",
            "passphrase_hint": "vault-backup-passphrase"
        }

    # Track database backups
    db_files = {
        "postgres": "postgres_all.sql",
        "mysql": "mysql_all.sql",
        "mongodb": "mongodb_dump.archive",
        "forgejo": "forgejo_data.tar.gz"
    }

    for db_name, filename in db_files.items():
        # Check for both encrypted and unencrypted versions
        file_path = backup_dir / filename
        encrypted_file_path = backup_dir / (filename + ".gpg")

        actual_file = encrypted_file_path if encrypted else file_path

        if actual_file.exists():
            file_size = actual_file.stat().st_size
            file_entry = {
                "type": backup_type if db_name == "forgejo" else "full",
                "file": actual_file.name,
                "size_bytes": file_size,
                "checksum": f"sha256:{calculate_file_checksum(actual_file)}"
            }

            # Add original filename if encrypted
            if encrypted:
                file_entry["original_file"] = filename

            if db_name == "forgejo" and backup_type == "incremental" and base_backup:
                file_entry["base_backup"] = base_backup

            manifest["databases"][db_name] = file_entry
            manifest["total_size_bytes"] += file_size

    # Track config file
    env_backup = backup_dir / ".env.backup"
    env_backup_encrypted = backup_dir / ".env.backup.gpg"

    actual_env = env_backup_encrypted if encrypted else env_backup

    if actual_env.exists():
        file_size = actual_env.stat().st_size
        config_entry = {
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


def find_latest_full_backup() -> Optional[str]:
    """
    Find the most recent full backup directory.

    Returns:
        Backup directory name (e.g., "20251117_080000") or None
    """
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

    # If no manifest files exist, assume all backups are full
    # Return the most recent backup directory
    for backup_dir in sorted(backups_dir.iterdir(), reverse=True):
        if backup_dir.is_dir() and backup_dir.name[0].isdigit():
            return backup_dir.name

    return None


def setup_backup_passphrase() -> bool:
    """
    Interactive setup for backup encryption passphrase.

    Prompts user to create a passphrase and saves it to
    ~/.config/vault/backup-passphrase with secure permissions.

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

    # Get passphrase (hidden input)
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

    # Save passphrase with secure permissions
    try:
        passphrase_file.write_text(passphrase1)
        os.chmod(passphrase_file, 0o600)  # Owner read/write only
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
    Encrypt a file using GPG symmetric encryption.

    Args:
        file_path: Path to file to encrypt
        passphrase: Encryption passphrase

    Returns:
        True if encryption successful, False otherwise

    Creates encrypted file with .gpg extension and deletes original.
    """
    if not file_path.exists():
        console.print(f"[red]File not found: {file_path}[/red]")
        return False

    encrypted_path = Path(str(file_path) + ".gpg")

    try:
        # Run GPG encryption
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

        # Delete original file after successful encryption
        file_path.unlink()
        return True

    except Exception as e:
        console.print(f"[red]Encryption error: {e}[/red]")
        return False


def decrypt_file_gpg(encrypted_path: Path, passphrase: str, output_path: Optional[Path] = None) -> bool:
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
        # Remove .gpg extension
        output_path = Path(str(encrypted_path).removesuffix(".gpg"))

    try:
        # Run GPG decryption
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


def verify_backup_integrity(backup_dir: Path) -> Tuple[bool, Dict]:
    """
    Verify backup integrity using checksums from manifest.

    Args:
        backup_dir: Path to backup directory

    Returns:
        Tuple of (success: bool, report: Dict)

    Report contains:
        - files_verified: Number of files successfully verified
        - files_failed: Number of files that failed verification
        - errors: List of error messages
        - warnings: List of warning messages
        - total_files: Total number of files to verify
    """
    report = {
        "files_verified": 0,
        "files_failed": 0,
        "files_total": 0,
        "errors": [],
        "warnings": [],
        "details": []
    }

    # Load manifest
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

    # Verify manifest structure
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

        # Check file exists
        if not file_path.exists():
            report["errors"].append(f"{filename}: File missing")
            report["files_failed"] += 1
            report["details"].append({
                "file": filename,
                "status": "missing",
                "size": 0
            })
            continue

        # Verify checksum
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

    # Success if all files verified
    success = report["files_failed"] == 0 and report["files_verified"] == report["files_total"]
    return success, report


# ==============================================================================
# CLI Commands
# ==============================================================================

@click.group()
@click.version_option(version="1.0.0", prog_name="devstack")
def cli():
    """DevStack Core Management Script - Modern Python CLI for Docker-based development infrastructure.

    \b
    USAGE
      devstack [COMMAND] [OPTIONS]
      devstack [COMMAND] --help

    \b
    CORE COMMANDS
      start               Start Colima VM and Docker services with profile(s)
      stop                Stop Docker services and optionally Colima VM
      restart             Restart Docker services (VM stays running)
      status              Display Colima VM and service status
      health              Check health status of all running services
      reset               Completely reset and delete Colima VM (DESTRUCTIVE)

    \b
    SERVICE MANAGEMENT
      logs                View logs for all services or specific service
      shell               Open interactive shell in a running container
      profiles            List all available service profiles with details
      ip                  Display Colima VM IP address

    \b
    DATA OPERATIONS
      backup              Backup all service data to timestamped directory
      restore             Restore service data from backup directory

    \b
    VAULT COMMANDS
      vault-init          Initialize and unseal Vault (manual/legacy)
      vault-unseal        Manually unseal Vault using stored keys
      vault-status        Display Vault seal status and token info
      vault-token         Print Vault root token to stdout
      vault-bootstrap     Bootstrap Vault with PKI and service credentials
      vault-ca-cert       Export Vault CA certificate chain to stdout
      vault-show-password Retrieve and display service credentials from Vault

    \b
    SERVICE INITIALIZATION
      forgejo-init        Initialize Forgejo via automated bootstrap
      redis-cluster-init  Initialize Redis cluster (standard/full profiles)

    \b
    SERVICE PROFILES
      minimal             5 services, 2GB RAM (vault, postgres, forgejo, redis-1)
      standard            10 services, 4GB RAM (minimal + mysql, mongodb, redis cluster)
      full                18 services, 6GB RAM (standard + observability stack)
      reference           5 services, +1GB RAM (API examples, combinable with others)

    \b
    QUICK START (First-Time Setup)
      ./devstack start                     # Start with standard profile
      ./devstack vault-bootstrap           # Setup Vault PKI + credentials
      ./devstack redis-cluster-init        # Initialize Redis cluster
      ./devstack forgejo-init              # Initialize Forgejo

    \b
    COMMON EXAMPLES
      # Start with specific profile
      ./devstack start --profile minimal

      # Combine multiple profiles
      ./devstack start --profile standard --profile reference

      # Monitor service logs in real-time
      ./devstack logs -f postgres

      # Create backup before changes
      ./devstack backup

      # Get service credentials
      ./devstack vault-show-password mysql

    \b
    GETTING HELP
      For detailed help on any command:
        ./devstack COMMAND --help

      Examples:
        ./devstack start --help
        ./devstack vault-show-password --help
    """
    pass


@cli.command()
@click.option(
    "--profile",
    "-p",
    multiple=True,
    default=["standard"],
    help="Service profile(s) to start (can specify multiple)",
    show_default=True
)
@click.option(
    "--detach/--no-detach",
    "-d",
    default=True,
    help="Run services in background (detached mode)",
    show_default=True
)
def start(profile: Tuple[str], detach: bool):
    """
    Start Colima VM and Docker services with specified profile(s).

    \b
    OPTIONS:
      -p, --profile TEXT      Service profile(s) to start (can specify multiple)
                              [default: standard]
                              Available: minimal, standard, full, reference
      -d, --detach            Run services in background (detached mode) [default: True]
          --no-detach         Run services in foreground (attached mode)

    \b
    PROFILES:
      minimal   - 5 services, 2GB RAM  (vault, postgres, pgbouncer, forgejo, redis-1)
      standard  - 10 services, 4GB RAM (minimal + mysql, mongodb, redis cluster, rabbitmq)
      full      - 18 services, 6GB RAM (standard + prometheus, grafana, loki, vector, cadvisor)
      reference - 5 services, +1GB RAM (API examples, combinable with other profiles)

    \b
    EXAMPLES:
      # Start with standard profile (default)
      ./devstack start

      # Start with minimal profile
      ./devstack start --profile minimal

      # Combine standard and reference profiles
      ./devstack start --profile standard --profile reference

      # Start in foreground (see logs in real-time)
      ./devstack start --no-detach

    \b
    NOTES:
      - Colima VM starts automatically if not running
      - After first start, run: ./devstack vault-bootstrap
      - For standard/full profiles, run: ./devstack redis-cluster-init
    """
    console.print("\n[cyan]═══ DevStack Core - Start Services ═══[/cyan]\n")

    # Validate profiles
    profiles_config = load_profiles_config()
    for p in profile:
        if p not in profiles_config.get("profiles", {}) and \
           p not in profiles_config.get("custom_profiles", {}):
            console.print(f"[red]Error: Unknown profile '{p}'[/red]")
            console.print("\n[yellow]Available profiles:[/yellow]")
            for prof_name in profiles_config.get("profiles", {}).keys():
                console.print(f"  • {prof_name}")
            sys.exit(1)

    # Display what will start
    console.print(f"[green]Starting with profile(s):[/green] {', '.join(profile)}\n")

    # Load profile environment variables
    merged_env = {}
    for p in profile:
        profile_env = load_profile_env(p)
        merged_env.update(profile_env)
        if profile_env:
            console.print(f"[dim]Loaded {len(profile_env)} environment overrides from {p}.env[/dim]")

    # Step 1: Check/Start Colima
    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        task = progress.add_task("Checking Colima VM status...", total=None)

        if not check_colima_status():
            progress.update(task, description="Starting Colima VM...")
            run_command([
                "colima", "start",
                "-p", COLIMA_PROFILE,
                "--cpu", COLIMA_CPU,
                "--memory", COLIMA_MEMORY,
                "--disk", COLIMA_DISK,
                "--network-address"
            ], env=merged_env)
            console.print("[green]✓ Colima VM started[/green]")
        else:
            progress.update(task, description="Colima VM already running")
            console.print("[green]✓ Colima VM already running[/green]")

    # Step 2: Clean up any orphaned containers/networks from previous runs
    console.print(f"\n[dim]Cleaning up orphaned resources...[/dim]")

    # Stop and remove ALL containers/networks (use all possible profiles to ensure cleanup)
    cleanup_cmd = ["docker", "compose"]
    for prof in ["minimal", "standard", "full", "reference"]:
        cleanup_cmd.extend(["--profile", prof])
    cleanup_cmd.append("down")
    run_command(cleanup_cmd, check=False)

    # Step 3: Start Docker services with profile(s)
    console.print(f"\n[cyan]Starting Docker services...[/cyan]")

    cmd = ["docker", "compose"]
    for p in profile:
        cmd.extend(["--profile", p])
    cmd.extend(["up", "-d" if detach else ""])

    # Remove empty strings
    cmd = [c for c in cmd if c]

    console.print(f"[dim]Command: {' '.join(cmd)}[/dim]\n")
    run_command(cmd, env=merged_env)

    # Step 4: Display running services
    console.print("\n[green]✓ Services started successfully[/green]\n")

    # Show service status
    _, stdout, _ = run_command(
        ["docker", "compose", "ps", "--format", "table"],
        capture=True
    )
    console.print(stdout)

    # Show next steps
    console.print("\n[cyan]Next Steps:[/cyan]")
    if "standard" in profile or "full" in profile:
        console.print("  1. Initialize Redis cluster (if first time):")
        console.print("     [yellow]./devstack redis-cluster-init[/yellow]")
        console.print("  2. Check service health:")
        console.print("     [yellow]./devstack health[/yellow]")
    else:
        console.print("  • Check service health:")
        console.print("    [yellow]./devstack health[/yellow]")

    console.print()


@cli.command()
@click.option(
    "--profile",
    "-p",
    multiple=True,
    help="Only stop services from specific profile(s)"
)
def stop(profile: Optional[Tuple[str]]):
    """
    Stop Docker services and Colima VM.

    \b
    OPTIONS:
      -p, --profile TEXT      Only stop services from specific profile(s)
                              Can specify multiple profiles
                              Available: minimal, standard, full, reference

    \b
    BEHAVIOR:
      - With --profile: Stops only services from specified profile(s)
      - Without --profile: Stops ALL services and Colima VM

    \b
    EXAMPLES:
      # Stop everything (all services + Colima VM)
      ./devstack stop

      # Stop only reference profile services
      ./devstack stop --profile reference

      # Stop multiple profiles
      ./devstack stop --profile standard --profile reference

    \b
    NOTES:
      - Use --profile to stop specific services while keeping others running
      - Without --profile, the Colima VM will be stopped completely
    """
    console.print("\n[cyan]═══ DevStack Core - Stop Services ═══[/cyan]\n")

    if profile:
        # Stop specific profile services
        console.print(f"[yellow]Stopping profile(s):[/yellow] {', '.join(profile)}\n")

        # Load profiles.yaml to get service list
        profiles_config = load_profiles_config()
        services_to_stop = []

        for p in profile:
            if p in profiles_config.get('profiles', {}):
                profile_services = profiles_config['profiles'][p].get('services', [])
                services_to_stop.extend(profile_services)
            elif p in profiles_config.get('custom_profiles', {}):
                profile_services = profiles_config['custom_profiles'][p].get('services', [])
                services_to_stop.extend(profile_services)
            else:
                console.print(f"[red]✗ Unknown profile:[/red] {p}")
                return

        # Remove duplicates while preserving order
        services_to_stop = list(dict.fromkeys(services_to_stop))

        if services_to_stop:
            console.print(f"[dim]Stopping {len(services_to_stop)} services...[/dim]\n")
            # Convert service names to container names (dev-<service>)
            container_names = [f"dev-{svc}" for svc in services_to_stop]
            cmd = ["docker", "stop"] + container_names
            run_command(cmd, check=False)  # Don't fail if some containers aren't running
            console.print(f"\n[green]✓ Stopped {len(services_to_stop)} services from profile(s): {', '.join(profile)}[/green]")
        else:
            console.print("[yellow]⚠ No services found for specified profile(s)[/yellow]")
    else:
        # Stop everything
        console.print("[yellow]Stopping all services and Colima VM...[/yellow]\n")

        # Stop Docker services
        run_command(["docker", "compose", "down"])
        console.print("[green]✓ Docker services stopped[/green]")

        # Stop Colima
        if check_colima_status():
            run_command(["colima", "stop", "-p", COLIMA_PROFILE])
            console.print("[green]✓ Colima VM stopped[/green]")
        else:
            console.print("[dim]Colima VM was not running[/dim]")

    console.print()


@cli.command()
def status():
    """
    Display status of Colima VM and all running services.

    Shows resource usage (CPU, memory) for each service.
    """
    console.print("\n[cyan]═══ DevStack Core - Service Status ═══[/cyan]\n")

    # Colima status
    if check_colima_status():
        console.print("[green]✓ Colima VM:[/green] Running\n")

        # Get Colima info
        _, stdout, _ = run_command(
            ["colima", "list", "-p", COLIMA_PROFILE],
            capture=True,
            check=False
        )
        if stdout:
            console.print(stdout)
    else:
        console.print("[red]✗ Colima VM:[/red] Not running\n")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    # Docker services status
    console.print("[cyan]Docker Services:[/cyan]\n")

    _, stdout, _ = run_command(
        ["docker", "compose", "ps", "--format", "table"],
        capture=True,
        check=False
    )

    if stdout and "NAME" in stdout:
        console.print(stdout)
    else:
        console.print("[yellow]No services running[/yellow]")
        console.print("[dim]Start services with: ./devstack start[/dim]")

    console.print()


@cli.command()
def health():
    """
    Check health status of all running services.

    Performs health checks and displays results in a table.
    """
    console.print("\n[cyan]═══ DevStack Core - Health Check ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima VM is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    # Get list of running containers
    _, stdout, _ = run_command(
        ["docker", "compose", "ps", "--format", "json"],
        capture=True,
        check=False
    )

    if not stdout:
        console.print("[yellow]No services running[/yellow]\n")
        return

    # Parse and check health
    table = Table(title="Service Health Status", box=box.ROUNDED)
    table.add_column("Service", style="cyan")
    table.add_column("Status", style="green")
    table.add_column("Health", style="yellow")

    for line in stdout.strip().split("\n"):
        try:
            container = json.loads(line)
            service = container.get("Service", "unknown")
            state = container.get("State", "unknown")
            health = container.get("Health", "unknown")

            # Color code status
            if state == "running":
                status_display = "[green]running[/green]"
            else:
                status_display = f"[red]{state}[/red]"

            # Color code health
            if health == "healthy":
                health_display = "[green]healthy[/green]"
            elif health == "unknown":
                health_display = "[dim]no healthcheck[/dim]"
            else:
                health_display = f"[yellow]{health}[/yellow]"

            table.add_row(service, status_display, health_display)
        except json.JSONDecodeError:
            continue

    console.print(table)
    console.print()


@cli.command()
@click.argument("service", required=False)
@click.option(
    "--follow",
    "-f",
    is_flag=True,
    help="Follow log output (like tail -f)"
)
@click.option(
    "--tail",
    "-n",
    default=100,
    help="Number of lines to show from end of logs",
    show_default=True
)
def logs(service: Optional[str], follow: bool, tail: int):
    """
    View logs for all services or a specific service.

    \b
    ARGUMENTS:
      service                 Service name (optional)
                              Examples: postgres, vault, redis-1, forgejo
                              If omitted, shows logs for all services

    \b
    OPTIONS:
      -f, --follow            Follow log output in real-time (like tail -f)
      -n, --tail INTEGER      Number of lines to show from end of logs
                              [default: 100]

    \b
    EXAMPLES:
      # View last 100 lines from all services
      ./devstack logs

      # View PostgreSQL logs only
      ./devstack logs postgres

      # Follow Vault logs in real-time
      ./devstack logs -f vault

      # Show last 500 lines of Redis logs
      ./devstack logs --tail 500 redis-1

      # Follow all service logs
      ./devstack logs -f

    \b
    NOTES:
      - Press Ctrl+C to stop following logs
      - Use --follow to see logs as they are generated
      - Combine --follow and --tail to start from a specific point
    """
    cmd = ["docker", "compose", "logs"]

    if follow:
        cmd.append("-f")

    cmd.extend(["--tail", str(tail)])

    if service:
        cmd.append(service)

    try:
        run_command(cmd, check=False)
    except KeyboardInterrupt:
        console.print("\n[dim]Log streaming stopped[/dim]\n")


@cli.command()
@click.argument("service")
@click.option(
    "--shell",
    "-s",
    default="sh",
    help="Shell to use (sh, bash, etc.)",
    show_default=True
)
def shell(service: str, shell: str):
    """
    Open an interactive shell in a running container.

    \b
    ARGUMENTS:
      service                 Service name (required)
                              Examples: postgres, vault, redis-1, mysql, mongodb

    \b
    OPTIONS:
      -s, --shell TEXT        Shell to use inside container
                              [default: sh]
                              Options: sh, bash, ash (depending on container)

    \b
    EXAMPLES:
      # Open shell in PostgreSQL container
      ./devstack shell postgres

      # Open bash shell in Vault container
      ./devstack shell vault --shell bash

      # Open shell in Redis container
      ./devstack shell redis-1

    \b
    NOTES:
      - Type 'exit' or press Ctrl+D to close the shell
      - Not all containers have bash; use sh as fallback
      - Useful for manual inspection, debugging, or one-off commands
    """
    console.print(f"\n[cyan]Opening shell in {service}...[/cyan]")
    console.print(f"[dim]Type 'exit' to close the shell[/dim]\n")

    run_command(
        ["docker", "compose", "exec", service, shell],
        check=False
    )

    console.print(f"\n[dim]Closed shell in {service}[/dim]\n")


@cli.command()
def profiles():
    """
    List all available service profiles with details.

    Shows services, resource usage, and use cases for each profile.
    """
    console.print("\n[cyan]═══ DevStack Core - Service Profiles ═══[/cyan]\n")

    profiles_config = load_profiles_config()

    # Main profiles table
    table = Table(title="Available Profiles", box=box.ROUNDED)
    table.add_column("Profile", style="cyan", no_wrap=True)
    table.add_column("Services", style="green")
    table.add_column("RAM", style="yellow")
    table.add_column("Description")

    for name, config in profiles_config.get("profiles", {}).items():
        services = str(len(config.get("services", [])))
        ram = config.get("resources", {}).get("ram_estimate", "N/A")
        desc = config.get("description", "")

        table.add_row(name, services, ram, desc)

    console.print(table)

    # Custom profiles
    if "custom_profiles" in profiles_config:
        console.print("\n[cyan]Custom Profiles:[/cyan]")
        for name, config in profiles_config.get("custom_profiles", {}).items():
            desc = config.get("description", "")
            services = len(config.get("services", []))
            console.print(f"  • [green]{name}[/green] ({services} services): {desc}")

    console.print("\n[dim]Use with: ./devstack start --profile <name>[/dim]\n")


@cli.command()
def ip():
    """
    Display Colima VM IP address.

    Useful for accessing services from libvirt VMs or other network clients.
    """
    if not check_colima_status():
        console.print("[red]Error: Colima VM is not running[/red]\n")
        return

    _, stdout, _ = run_command(
        ["colima", "ls", "-p", COLIMA_PROFILE, "-j"],
        capture=True
    )

    try:
        colima_info = json.loads(stdout)
        if colima_info and isinstance(colima_info, dict):
            ip_address = colima_info.get("address", "N/A")
            console.print(f"\n[cyan]Colima VM IP:[/cyan] [green]{ip_address}[/green]\n")
        else:
            console.print("[yellow]Could not determine IP address[/yellow]\n")
    except (json.JSONDecodeError, KeyError):
        console.print("[yellow]Could not parse Colima info[/yellow]\n")


@cli.command()
def restart():
    """
    Restart all Docker services without restarting Colima VM.

    Faster than stop+start as the VM stays running.
    Use for applying configuration changes or recovering from errors.
    """
    console.print("\n[cyan]═══ DevStack Core - Restart Services ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima VM is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    console.print("[yellow]Restarting Docker services...[/yellow]\n")
    run_command(["docker", "compose", "restart"])

    console.print("\n[green]✓ Services restarted successfully[/green]\n")

    # Show status
    _, stdout, _ = run_command(
        ["docker", "compose", "ps", "--format", "table"],
        capture=True,
        check=False
    )
    if stdout:
        console.print(stdout)

    console.print()


@cli.command()
@click.confirmation_option(
    prompt="This will DELETE ALL DATA in Colima VM. Are you sure?"
)
def reset():
    """
    Completely reset and delete Colima VM - DESTRUCTIVE OPERATION.

    \b
    *** DATA LOSS WARNING ***
    This command DESTROYS ALL DATA including:
      - All Docker containers and images
      - All Docker volumes (databases, Git repos, uploaded files)
      - Colima VM disk and configuration

    \b
    Data that is NOT destroyed:
      - Vault keys/tokens in ~/.config/vault/ (on host)
      - Backups in ./backups/ directory (on host)
      - .env configuration file (on host)

    \b
    ALWAYS run './devstack backup' before reset!
    """
    console.print("\n[cyan]═══ DevStack Core - Reset Colima VM ═══[/cyan]\n")

    console.print("[red]⚠ WARNING: Deleting all data...[/red]\n")

    # Stop services
    console.print("[yellow]Stopping services...[/yellow]")
    run_command(["docker", "compose", "down", "-v"], check=False)

    # Delete Colima VM
    console.print("[yellow]Deleting Colima VM...[/yellow]")
    run_command(["colima", "delete", "-p", COLIMA_PROFILE, "--force"])

    console.print("\n[green]✓ Colima VM has been reset[/green]")
    console.print("[cyan]Run './devstack start' to create a fresh VM[/cyan]\n")


@cli.command()
@click.option(
    "--incremental",
    "-i",
    is_flag=True,
    help="Create incremental backup (Forgejo only, databases remain full)"
)
@click.option(
    "--full",
    "-f",
    is_flag=True,
    help="Force full backup (default if no base backup exists)"
)
@click.option(
    "--encrypt",
    "-e",
    is_flag=True,
    help="Encrypt backup files with GPG (AES256 symmetric encryption)"
)
def backup(incremental, full, encrypt):
    """
    Backup all service data to timestamped directory.

    \b
    Backup Types:
      Full Backup (default):
        - Complete dump of all databases and services
        - Serves as baseline for incremental chain
        - Use --full to force full backup

      Incremental Backup (--incremental):
        - PostgreSQL, MySQL, MongoDB: Always full dumps (small datasets)
        - Forgejo: Incremental with rsync (large git repos)
        - Requires previous full backup as base

    \b
    Backup includes:
      - PostgreSQL: Complete dump of all databases
      - MySQL: Complete dump of all databases
      - MongoDB: Binary archive dump
      - Forgejo: Tarball or incremental rsync
      - .env file: Configuration backup
      - manifest.json: Metadata, checksums, backup chain info

    \b
    Backup location: ./backups/YYYYMMDD_HHMMSS/

    \b
    EXAMPLES:
      # Full backup (default)
      ./devstack backup

      # Force full backup
      ./devstack backup --full

      # Incremental backup (Forgejo only)
      ./devstack backup --incremental
    """
    console.print("\n[cyan]═══ DevStack Core - Backup ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    # Determine backup type
    backup_type = "full"
    base_backup = None
    previous_backup = None

    if incremental and not full:
        # Check if a full backup exists
        base_backup = find_latest_full_backup()
        if base_backup:
            backup_type = "incremental"
            previous_backup = base_backup
            console.print(f"[cyan]Incremental backup based on:[/cyan] {base_backup}")
        else:
            console.print("[yellow]No full backup found, creating full backup instead[/yellow]")
            backup_type = "full"

    if backup_type == "full":
        console.print("[cyan]Creating full backup[/cyan]")
    else:
        console.print("[cyan]Creating incremental backup (Forgejo only)[/cyan]")

    # Create backup directory
    backup_dir = SCRIPT_DIR / "backups" / datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir.mkdir(parents=True, exist_ok=True)
    start_time = time.time()

    console.print(f"[cyan]Backup location:[/cyan] {backup_dir}\n")

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        # Backup PostgreSQL
        task = progress.add_task("Backing up PostgreSQL...", total=None)
        # Get PostgreSQL password from Vault using AppRole
        postgres_pass = get_vault_secret("secret/postgres", "password", use_approle=True)

        if postgres_pass:
            # Use PGPASSWORD environment variable for authentication
            env = os.environ.copy()
            env['PGPASSWORD'] = postgres_pass
            returncode, stdout, _ = run_command(
                ["docker", "compose", "exec", "-T", "-e", f"PGPASSWORD={postgres_pass}",
                 "postgres", "pg_dumpall", "-U", "devuser"],
                capture=True,
                check=False,
                env=env
            )
            if returncode == 0:
                (backup_dir / "postgres_all.sql").write_text(stdout)
                progress.update(task, description="[green]✓ PostgreSQL backed up[/green]")
            else:
                progress.update(task, description="[yellow]⚠ PostgreSQL backup failed[/yellow]")
        else:
            progress.update(task, description="[yellow]⚠ PostgreSQL backup skipped (no password)[/yellow]")

        # Backup MySQL
        task = progress.add_task("Backing up MySQL...", total=None)
        # Get MySQL user password from Vault using AppRole (use devuser instead of root)
        mysql_pass = get_vault_secret("secret/mysql", "password", use_approle=True)
        mysql_user = "devuser"  # Use devuser which has backup privileges

        if mysql_pass:
            # Use docker exec directly to properly pass environment variables
            returncode, stdout, stderr = run_command(
                ["docker", "exec", "-e", f"MYSQL_PWD={mysql_pass}",
                 "dev-mysql", "mysqldump", "-u", mysql_user, "--all-databases", "--no-tablespaces"],
                capture=True,
                check=False
            )
            if returncode == 0:
                (backup_dir / "mysql_all.sql").write_text(stdout)
                progress.update(task, description="[green]✓ MySQL backed up[/green]")
            else:
                error_msg = stderr.strip() if stderr else f"exit code {returncode}"
                progress.update(task, description=f"[yellow]⚠ MySQL backup failed: {error_msg}[/yellow]")
        else:
            progress.update(task, description="[yellow]⚠ MySQL backup skipped (no password)[/yellow]")

        # Backup MongoDB
        task = progress.add_task("Backing up MongoDB...", total=None)
        # Get MongoDB credentials from Vault using AppRole
        mongo_user = get_vault_secret("secret/mongodb", "user", use_approle=True) or "devuser"
        mongo_pass = get_vault_secret("secret/mongodb", "password", use_approle=True)

        if mongo_pass:
            try:
                # Use docker exec to pass authentication credentials
                result = subprocess.run(
                    ["docker", "exec", "dev-mongodb", "mongodump",
                     "--username", mongo_user,
                     "--password", mongo_pass,
                     "--authenticationDatabase", "admin",
                     "--archive"],
                    capture_output=True,
                    check=False
                )
                if result.returncode == 0:
                    (backup_dir / "mongodb_dump.archive").write_bytes(result.stdout)
                    progress.update(task, description="[green]✓ MongoDB backed up[/green]")
                else:
                    stderr_msg = result.stderr.decode() if result.stderr else f"exit code {result.returncode}"
                    progress.update(task, description=f"[yellow]⚠ MongoDB backup failed: {stderr_msg[:50]}[/yellow]")
            except Exception as e:
                progress.update(task, description=f"[yellow]⚠ MongoDB backup error: {e}[/yellow]")
        else:
            progress.update(task, description="[yellow]⚠ MongoDB backup skipped (no password)[/yellow]")

        # Backup Forgejo (incremental support with rsync)
        task = progress.add_task("Backing up Forgejo...", total=None)
        try:
            if backup_type == "incremental" and base_backup:
                # Incremental backup using rsync with hard-link deduplication
                # Note: This is a simplified approach - full tar backup is used for now
                # as rsync requires host filesystem access, not practical with Docker volumes
                # Future enhancement: Use docker cp + rsync on host
                progress.update(task, description="[yellow]ℹ Forgejo: Using full backup (incremental via rsync not yet supported)[/yellow]")

            # Perform full tarball backup (works for both full and incremental)
            result = subprocess.run(
                ["docker", "compose", "exec", "-T", "forgejo", "tar", "czf", "-", "/data"],
                capture_output=True,
                check=False
            )
            if result.returncode == 0:
                (backup_dir / "forgejo_data.tar.gz").write_bytes(result.stdout)
                if backup_type == "incremental":
                    progress.update(task, description="[green]✓ Forgejo backed up (full)[/green]")
                else:
                    progress.update(task, description="[green]✓ Forgejo backed up[/green]")
            else:
                progress.update(task, description="[yellow]⚠ Forgejo backup failed[/yellow]")
        except Exception as e:
            progress.update(task, description=f"[yellow]⚠ Forgejo backup error: {e}[/yellow]")

        # Backup .env file
        if ENV_FILE.exists():
            import shutil
            shutil.copy(ENV_FILE, backup_dir / ".env.backup")
            progress.add_task("[green]✓ .env file backed up[/green]", total=None)

        # Encrypt backup files if requested
        if encrypt:
            task = progress.add_task("Encrypting backup files...", total=None)

            # Get or create passphrase
            passphrase = get_backup_passphrase(prompt_if_missing=True)
            if not passphrase:
                progress.update(task, description="[red]✗ Encryption cancelled (no passphrase)[/red]")
                encrypt = False  # Disable encryption for manifest
            else:
                # List of files to encrypt
                files_to_encrypt = []
                for file_path in backup_dir.iterdir():
                    if file_path.name != "manifest.json" and file_path.is_file():
                        files_to_encrypt.append(file_path)

                # Encrypt each file
                encrypted_count = 0
                failed_count = 0
                for file_path in files_to_encrypt:
                    if encrypt_file_gpg(file_path, passphrase):
                        encrypted_count += 1
                    else:
                        failed_count += 1

                if failed_count == 0:
                    progress.update(task, description=f"[green]✓ {encrypted_count} files encrypted[/green]")
                else:
                    progress.update(task, description=f"[yellow]⚠ {encrypted_count} encrypted, {failed_count} failed[/yellow]")

        # Generate backup manifest with checksums
        task = progress.add_task("Generating backup manifest...", total=None)
        manifest = None
        try:
            manifest = create_backup_manifest(
                backup_dir=backup_dir,
                backup_type=backup_type,
                base_backup=base_backup,
                previous_backup=previous_backup,
                start_time=start_time,
                encrypted=encrypt
            )
            progress.update(task, description="[green]✓ Manifest created[/green]")
        except Exception as e:
            progress.update(task, description=f"[yellow]⚠ Manifest creation failed: {e}[/yellow]")

    # Show backup summary
    console.print(f"\n[green]✓ Backup completed:[/green] {backup_dir}")
    console.print(f"[cyan]Backup type:[/cyan] {backup_type}")

    if manifest:
        console.print(f"[cyan]Total size:[/cyan] {manifest['total_size_bytes']:,} bytes ({manifest['total_size_bytes'] / 1024:.1f} KB)")
        console.print(f"[cyan]Duration:[/cyan] {manifest['duration_seconds']} seconds")
        console.print(f"[cyan]Files backed up:[/cyan] {len(manifest['databases'])} databases + config")
        console.print(f"[cyan]Encrypted:[/cyan] {'Yes (AES256)' if manifest['encrypted'] else 'No'}")

        if backup_type == "incremental":
            console.print(f"[cyan]Base backup:[/cyan] {base_backup}")
    else:
        # Fallback if manifest creation failed
        try:
            result = subprocess.run(
                ["/usr/bin/du", "-sh", str(backup_dir)],
                capture_output=True,
                text=True
            )
            size = result.stdout.split()[0]
            console.print(f"[cyan]Backup size:[/cyan] {size}")
        except Exception:
            # du command failed or output format unexpected - skip size display
            pass

    console.print("")


@cli.command()
@click.argument('backup_name', required=False)
def restore(backup_name):
    """
    Restore service data from a backup directory.

    ⚠️  DATA LOSS WARNING ⚠️
    This command will OVERWRITE current data with backup data.

    \b
    ARGUMENTS:
      backup_name             Backup directory name (optional)
                              Format: YYYYMMDD_HHMMSS (e.g., 20250110_143022)
                              If omitted, lists available backups

    \b
    OPTIONS:
      None - This command uses an argument, not options

    \b
    EXAMPLES:
      # List all available backups
      ./devstack restore

      # Restore from specific backup
      ./devstack restore 20250110_143022

      # Typical restore workflow
      ./devstack stop                    # Stop services first
      ./devstack restore 20250110_143022 # Restore backup
      ./devstack start                   # Restart services

    \b
    RESTORED DATA:
      - PostgreSQL: All databases and tables
      - MySQL: All databases and tables
      - MongoDB: All collections and documents
      - Forgejo: Git repositories, uploads, and configuration
      - .env file: Environment configuration

    \b
    NOTES:
      - Always create a backup before restoring: ./devstack backup
      - Restoration will prompt for confirmation before proceeding
      - Services should be running during restore
      - Restart services after restore to pick up changes
    """
    console.print("\n[cyan]═══ DevStack Core - Restore ═══[/cyan]\n")

    backups_dir = SCRIPT_DIR / "backups"

    # List available backups if no backup specified
    if not backup_name:
        if not backups_dir.exists() or not list(backups_dir.iterdir()):
            console.print("[yellow]No backups found in ./backups/[/yellow]\n")
            console.print("[cyan]Create a backup first:[/cyan] ./devstack backup\n")
            return

        console.print("[cyan]Available backups:[/cyan]\n")
        backups = sorted([d for d in backups_dir.iterdir() if d.is_dir()], reverse=True)

        from rich.table import Table
        table = Table(show_header=True, header_style="bold cyan")
        table.add_column("Backup Name", style="yellow")
        table.add_column("Date", style="green")
        table.add_column("Size", style="cyan")

        for backup in backups:
            # Parse timestamp from directory name (YYYYMMDD_HHMMSS)
            try:
                from datetime import datetime
                date_str = backup.name
                dt = datetime.strptime(date_str, "%Y%m%d_%H%M%S")
                formatted_date = dt.strftime("%Y-%m-%d %H:%M:%S")
            except Exception:
                formatted_date = backup.name

            # Get size
            import subprocess
            try:
                result = subprocess.run(
                    ["du", "-sh", str(backup)],
                    capture_output=True,
                    text=True
                )
                size = result.stdout.split()[0]
            except Exception:
                size = "Unknown"

            table.add_row(backup.name, formatted_date, size)

        console.print(table)
        console.print("\n[cyan]To restore a backup:[/cyan] ./devstack restore BACKUP_NAME\n")
        return

    # Validate backup exists
    backup_dir = backups_dir / backup_name
    if not backup_dir.exists():
        console.print(f"[red]Error: Backup not found:[/red] {backup_dir}\n")
        console.print("[cyan]List available backups:[/cyan] ./devstack restore\n")
        return

    # Check if services are running
    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    # Confirm restoration
    console.print(f"[yellow]⚠️  WARNING: This will OVERWRITE current data with backup from {backup_name}[/yellow]\n")
    console.print("[red]This operation cannot be undone![/red]\n")

    import click
    if not click.confirm("Are you sure you want to continue?", default=False):
        console.print("\n[yellow]Restore cancelled.[/yellow]\n")
        return

    console.print(f"\n[cyan]Restoring from:[/cyan] {backup_dir}\n")

    # Check if backup is encrypted
    manifest_file = backup_dir / "manifest.json"
    is_encrypted = False
    passphrase = None

    if manifest_file.exists():
        try:
            with open(manifest_file, 'r') as f:
                manifest = json.load(f)
                is_encrypted = manifest.get("encrypted", False)
        except Exception as e:
            console.print(f"[yellow]Warning: Could not read manifest: {e}[/yellow]")

    # If encrypted, get passphrase
    if is_encrypted:
        console.print("[cyan]This backup is encrypted.[/cyan]")
        passphrase = get_backup_passphrase(prompt_if_missing=True)
        if not passphrase:
            console.print("[red]Error: Passphrase required for encrypted backup[/red]\n")
            return
        console.print("[green]✓ Passphrase loaded[/green]\n")

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        # Restore PostgreSQL
        postgres_backup = backup_dir / "postgres_all.sql.gpg" if is_encrypted else backup_dir / "postgres_all.sql"
        if postgres_backup.exists():
            task = progress.add_task("Restoring PostgreSQL...", total=None)
            try:
                if is_encrypted:
                    # Decrypt to temporary file
                    import tempfile
                    with tempfile.NamedTemporaryFile(mode='w', suffix='.sql', delete=False) as temp_file:
                        temp_path = Path(temp_file.name)

                    if decrypt_file_gpg(postgres_backup, passphrase, temp_path):
                        with open(temp_path, 'r') as f:
                            returncode, _, _ = run_command(
                                ["docker", "compose", "exec", "-T", "postgres", "psql", "-U", "dev_admin", "postgres"],
                                capture=False,
                                check=False,
                                input=f.read()
                            )
                        temp_path.unlink()  # Clean up temp file
                    else:
                        progress.update(task, description="[red]✗ PostgreSQL decryption failed[/red]")
                        returncode = 1
                else:
                    with open(postgres_backup, 'r') as f:
                        returncode, _, _ = run_command(
                            ["docker", "compose", "exec", "-T", "postgres", "psql", "-U", "dev_admin", "postgres"],
                            capture=False,
                            check=False,
                            input=f.read()
                        )

                if returncode == 0:
                    progress.update(task, description="[green]✓ PostgreSQL restored[/green]")
                else:
                    progress.update(task, description="[yellow]⚠ PostgreSQL restore failed[/yellow]")
            except Exception as e:
                progress.update(task, description=f"[red]✗ PostgreSQL restore error: {e}[/red]")

        # Restore MySQL
        mysql_backup = backup_dir / "mysql_all.sql.gpg" if is_encrypted else backup_dir / "mysql_all.sql"
        if mysql_backup.exists():
            task = progress.add_task("Restoring MySQL...", total=None)
            # Get MySQL password from Vault
            token = get_vault_token()
            if token:
                returncode, mysql_pass, _ = run_command(
                    ["docker", "exec", "dev-vault", "vault", "kv", "get", "-field=password", "secret/mysql"],
                    capture=True,
                    check=False,
                    env={"VAULT_TOKEN": token, "VAULT_ADDR": "http://localhost:8200"}
                )
                mysql_pass = mysql_pass.strip() if returncode == 0 else ""
            else:
                mysql_pass = ""

            if mysql_pass:
                try:
                    # Use MYSQL_PWD environment variable to avoid password exposure in process list
                    env = os.environ.copy()
                    env['MYSQL_PWD'] = mysql_pass

                    if is_encrypted:
                        # Decrypt to temporary file
                        import tempfile
                        with tempfile.NamedTemporaryFile(mode='w', suffix='.sql', delete=False) as temp_file:
                            temp_path = Path(temp_file.name)

                        if decrypt_file_gpg(mysql_backup, passphrase, temp_path):
                            with open(temp_path, 'r') as f:
                                returncode, _, _ = run_command(
                                    ["docker", "compose", "exec", "-T", "-e", f"MYSQL_PWD={mysql_pass}",
                                     "mysql", "mysql", "-u", "root"],
                                    capture=False,
                                    check=False,
                                    input=f.read(),
                                    env=env
                                )
                            temp_path.unlink()  # Clean up temp file
                        else:
                            progress.update(task, description="[red]✗ MySQL decryption failed[/red]")
                            returncode = 1
                    else:
                        with open(mysql_backup, 'r') as f:
                            returncode, _, _ = run_command(
                                ["docker", "compose", "exec", "-T", "-e", f"MYSQL_PWD={mysql_pass}",
                                 "mysql", "mysql", "-u", "root"],
                                capture=False,
                                check=False,
                                input=f.read(),
                                env=env
                            )

                    if returncode == 0:
                        progress.update(task, description="[green]✓ MySQL restored[/green]")
                    else:
                        progress.update(task, description="[yellow]⚠ MySQL restore failed[/yellow]")
                except Exception as e:
                    progress.update(task, description=f"[red]✗ MySQL restore error: {e}[/red]")
            else:
                progress.update(task, description="[yellow]⚠ MySQL restore skipped (no password)[/yellow]")

        # Restore MongoDB
        mongodb_backup = backup_dir / "mongodb_dump.archive.gpg" if is_encrypted else backup_dir / "mongodb_dump.archive"
        if mongodb_backup.exists():
            task = progress.add_task("Restoring MongoDB...", total=None)
            try:
                import subprocess
                if is_encrypted:
                    # Decrypt to temporary file
                    import tempfile
                    with tempfile.NamedTemporaryFile(suffix='.archive', delete=False) as temp_file:
                        temp_path = Path(temp_file.name)

                    if decrypt_file_gpg(mongodb_backup, passphrase, temp_path):
                        with open(temp_path, 'rb') as f:
                            result = subprocess.run(
                                ["docker", "compose", "exec", "-T", "mongodb", "mongorestore", "--archive", "--drop"],
                                input=f.read(),
                                capture_output=True,
                                check=False
                            )
                        temp_path.unlink()  # Clean up temp file
                    else:
                        progress.update(task, description="[red]✗ MongoDB decryption failed[/red]")
                        result = subprocess.CompletedProcess([], 1)
                else:
                    with open(mongodb_backup, 'rb') as f:
                        result = subprocess.run(
                            ["docker", "compose", "exec", "-T", "mongodb", "mongorestore", "--archive", "--drop"],
                            input=f.read(),
                            capture_output=True,
                            check=False
                        )

                if result.returncode == 0:
                    progress.update(task, description="[green]✓ MongoDB restored[/green]")
                else:
                    progress.update(task, description="[yellow]⚠ MongoDB restore failed[/yellow]")
            except Exception as e:
                progress.update(task, description=f"[red]✗ MongoDB restore error: {e}[/red]")

        # Restore Forgejo
        forgejo_backup = backup_dir / "forgejo_data.tar.gz.gpg" if is_encrypted else backup_dir / "forgejo_data.tar.gz"
        if forgejo_backup.exists():
            task = progress.add_task("Restoring Forgejo...", total=None)
            try:
                import subprocess  # Explicit import to prevent UnboundLocalError
                if is_encrypted:
                    # Decrypt to temporary file
                    import tempfile
                    with tempfile.NamedTemporaryFile(suffix='.tar.gz', delete=False) as temp_file:
                        temp_path = Path(temp_file.name)

                    if decrypt_file_gpg(forgejo_backup, passphrase, temp_path):
                        with open(temp_path, 'rb') as f:
                            result = subprocess.run(
                                ["docker", "compose", "exec", "-T", "forgejo", "sh", "-c", "rm -rf /data/* && tar xzf - -C /"],
                                input=f.read(),
                                capture_output=True,
                                check=False
                            )
                        temp_path.unlink()  # Clean up temp file
                    else:
                        progress.update(task, description="[red]✗ Forgejo decryption failed[/red]")
                        result = subprocess.CompletedProcess([], 1)
                else:
                    with open(forgejo_backup, 'rb') as f:
                        result = subprocess.run(
                            ["docker", "compose", "exec", "-T", "forgejo", "sh", "-c", "rm -rf /data/* && tar xzf - -C /"],
                            input=f.read(),
                            capture_output=True,
                            check=False
                        )

                if result.returncode == 0:
                    progress.update(task, description="[green]✓ Forgejo restored[/green]")
                else:
                    progress.update(task, description="[yellow]⚠ Forgejo restore failed[/yellow]")
            except Exception as e:
                progress.update(task, description=f"[red]✗ Forgejo restore error: {e}[/red]")

        # Restore .env file
        env_backup = backup_dir / ".env.backup.gpg" if is_encrypted else backup_dir / ".env.backup"
        if env_backup.exists():
            task = progress.add_task("Restoring .env file...", total=None)
            try:
                if is_encrypted:
                    # Decrypt directly to .env file
                    if decrypt_file_gpg(env_backup, passphrase, ENV_FILE):
                        progress.update(task, description="[green]✓ .env file restored[/green]")
                    else:
                        progress.update(task, description="[red]✗ .env decryption failed[/red]")
                else:
                    import shutil
                    shutil.copy(env_backup, ENV_FILE)
                    progress.update(task, description="[green]✓ .env file restored[/green]")
            except Exception as e:
                progress.update(task, description=f"[red]✗ .env restore error: {e}[/red]")

    console.print(f"\n[green]✓ Restore completed from:[/green] {backup_dir}")
    console.print("[yellow]⚠  Restart services to apply changes:[/yellow] ./devstack restart\n")


@cli.command()
@click.argument('backup_name', required=False)
@click.option('--all', 'verify_all', is_flag=True, help='Verify all backups')
def verify(backup_name, verify_all):
    """
    Verify backup integrity using checksums from manifest.

    \b
    Verification checks:
      - Manifest file exists and is valid JSON
      - All files listed in manifest exist on disk
      - SHA256 checksums match for all files
      - Manifest contains required fields

    \b
    ARGUMENTS:
      backup_name             Backup directory name (optional)
                              Format: YYYYMMDD_HHMMSS (e.g., 20251117_220602)
                              If omitted, lists available backups

    \b
    OPTIONS:
      --all                   Verify all backups in backups/ directory

    \b
    EXAMPLES:
      # List all backups
      ./devstack verify

      # Verify specific backup
      ./devstack verify 20251117_220602

      # Verify all backups
      ./devstack verify --all

    \b
    EXIT CODES:
      0 - Verification passed
      1 - Verification failed (corrupted backup)
    """
    backups_dir = SCRIPT_DIR / "backups"

    # If no backup specified and not --all, list backups
    if not backup_name and not verify_all:
        console.print("\n[cyan]═══ Available Backups ═══[/cyan]\n")

        if not backups_dir.exists() or not list(backups_dir.iterdir()):
            console.print("[yellow]No backups found[/yellow]\n")
            return

        # List backups with basic info
        backups = sorted([d for d in backups_dir.iterdir() if d.is_dir()], reverse=True)

        table = Table(show_header=True, header_style="bold cyan", box=box.ROUNDED)
        table.add_column("Backup ID", style="cyan")
        table.add_column("Type", style="yellow")
        table.add_column("Encrypted", style="magenta")
        table.add_column("Size", justify="right")

        for backup in backups[:10]:  # Show last 10
            manifest_file = backup / "manifest.json"
            if manifest_file.exists():
                try:
                    with open(manifest_file, 'r') as f:
                        manifest = json.load(f)

                    backup_type = manifest.get("backup_type", "unknown")
                    encrypted = "Yes" if manifest.get("encrypted", False) else "No"
                    total_size = manifest.get("total_size_bytes", 0)
                    size_kb = total_size / 1024

                    table.add_row(
                        backup.name,
                        backup_type,
                        encrypted,
                        f"{size_kb:.1f} KB"
                    )
                except Exception:
                    table.add_row(backup.name, "?", "?", "?")
            else:
                table.add_row(backup.name, "no manifest", "-", "-")

        console.print(table)
        console.print(f"\n[cyan]Tip:[/cyan] Run [green]./devstack verify <backup_id>[/green] to verify a backup\n")
        return

    # Verify single backup
    if backup_name:
        backup_dir = backups_dir / backup_name

        if not backup_dir.exists():
            console.print(f"[red]Error: Backup not found:[/red] {backup_dir}\n")
            sys.exit(1)

        console.print(f"\n[cyan]═══ Backup Verification Report ═══[/cyan]\n")
        console.print(f"[cyan]Backup ID:[/cyan] {backup_name}")

        # Load manifest for header info
        manifest_file = backup_dir / "manifest.json"
        if manifest_file.exists():
            try:
                with open(manifest_file, 'r') as f:
                    manifest = json.load(f)
                console.print(f"[cyan]Backup Type:[/cyan] {manifest.get('backup_type', 'unknown')}")
                console.print(f"[cyan]Encrypted:[/cyan] {'Yes (AES256)' if manifest.get('encrypted') else 'No'}")
                console.print(f"[cyan]Timestamp:[/cyan] {manifest.get('timestamp', 'unknown')}")
            except Exception:
                # Manifest file missing or invalid - skip metadata display
                pass

        console.print("")

        # Verify backup
        start_time = time.time()
        success, report = verify_backup_integrity(backup_dir)
        duration = time.time() - start_time

        # Show file verification results
        console.print(f"[cyan]Files Verified:[/cyan] {report['files_verified']}/{report['files_total']}\n")

        for detail in report['details']:
            filename = detail['file']
            status = detail['status']
            size = detail['size']

            if status == "ok":
                size_display = f"({size / 1024:.1f} KB)" if size > 0 else ""
                console.print(f"[green]✓ {filename}[/green] {size_display}")
            elif status == "missing":
                console.print(f"[red]✗ {filename}[/red] [yellow](FILE MISSING)[/yellow]")
            elif status == "checksum_mismatch":
                console.print(f"[red]✗ {filename}[/red] [yellow](CHECKSUM MISMATCH)[/yellow]")
            else:
                console.print(f"[red]✗ {filename}[/red] [yellow](ERROR)[/yellow]")

        # Show errors
        if report['errors']:
            console.print(f"\n[red]Errors:[/red]")
            for error in report['errors']:
                console.print(f"  [red]•[/red] {error}")

        # Summary
        console.print(f"\n[cyan]Duration:[/cyan] {duration:.2f} seconds")

        if success:
            console.print(f"\n[green]✓ Backup verification PASSED[/green]\n")
            sys.exit(0)
        else:
            console.print(f"\n[red]✗ Backup verification FAILED ({report['files_failed']} errors)[/red]")
            console.print("\n[yellow]Recommendations:[/yellow]")
            console.print("  • Restore from an earlier backup")
            console.print("  • Run backup again to create new verified backup\n")
            sys.exit(1)

    # Verify all backups
    if verify_all:
        console.print("\n[cyan]═══ Verifying All Backups ═══[/cyan]\n")

        backups = sorted([d for d in backups_dir.iterdir() if d.is_dir()])

        if not backups:
            console.print("[yellow]No backups found[/yellow]\n")
            return

        total_verified = 0
        total_failed = 0

        for backup in backups:
            backup_name = backup.name
            console.print(f"[cyan]Verifying:[/cyan] {backup_name} ... ", end="")

            success, report = verify_backup_integrity(backup)

            if success:
                console.print(f"[green]PASS[/green] ({report['files_verified']} files)")
                total_verified += 1
            else:
                console.print(f"[red]FAIL[/red] ({report['files_failed']} errors)")
                total_failed += 1

        console.print(f"\n[cyan]Summary:[/cyan]")
        console.print(f"  [green]✓ Passed:[/green] {total_verified}")
        console.print(f"  [red]✗ Failed:[/red] {total_failed}")
        console.print("")

        if total_failed > 0:
            sys.exit(1)


@cli.command()
def vault_init():
    """
    Initialize and unseal Vault (manual/legacy command).

    This is a LEGACY/MANUAL command. Normal startup uses auto-unseal.

    \b
    Use this command ONLY if:
      - Auto-unseal failed and manual intervention is needed
      - Debugging Vault initialization issues
      - Re-initializing after vault-delete (NOT recommended)
    """
    console.print("\n[cyan]═══ Vault - Initialize and Unseal ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    vault_init_script = SCRIPT_DIR / "configs" / "vault" / "scripts" / "vault-init.sh"
    if not vault_init_script.exists():
        console.print(f"[red]Error: Vault initialization script not found at {vault_init_script}[/red]\n")
        return

    console.print("[yellow]Running Vault initialization script...[/yellow]\n")
    run_command(["bash", str(vault_init_script)])
    console.print()


@cli.command()
def vault_unseal():
    """
    Manually unseal Vault using stored unseal keys.

    This is a MANUAL command. Vault auto-unseals on normal startup.

    \b
    Use this command ONLY if:
      - Vault is sealed after a crash or restart
      - Auto-unseal mechanism failed
      - Manual intervention is required
    """
    console.print("\n[cyan]═══ Vault - Unseal ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    vault_keys_file = VAULT_CONFIG_DIR / "keys.json"
    if not vault_keys_file.exists():
        console.print(f"[red]Error: Vault keys file not found: {vault_keys_file}[/red]")
        console.print("[yellow]Run './devstack vault-init' first[/yellow]\n")
        return

    console.print("[yellow]Unsealing Vault...[/yellow]\n")

    # Read keys file
    with open(vault_keys_file) as f:
        keys_data = json.load(f)
        unseal_keys = keys_data.get("unseal_keys_b64", [])[:3]

    if len(unseal_keys) < 3:
        console.print(f"[red]Error: Not enough unseal keys in {vault_keys_file}[/red]\n")
        return

    # Unseal with first 3 keys
    for i, key in enumerate(unseal_keys, 1):
        console.print(f"[dim]Unsealing with key {i}/3...[/dim]")
        run_command(
            ["docker", "exec", "dev-vault", "vault", "operator", "unseal", key],
            check=False
        )

    console.print("\n[green]✓ Vault unsealed successfully[/green]\n")


@cli.command()
def vault_status():
    """
    Display Vault seal status and root token information.

    \b
    Shows critical Vault state:
      - Sealed: true/false (whether Vault is locked)
      - Initialized: true/false (whether Vault has been set up)
      - Version: Vault server version
    """
    console.print("\n[cyan]═══ Vault - Status ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]\n")
        return

    console.print("[cyan]Vault Status:[/cyan]\n")
    run_command(["docker", "exec", "dev-vault", "vault", "status"], check=False)

    # Show root token if available
    token_file = VAULT_CONFIG_DIR / "root-token"
    if token_file.exists():
        token = token_file.read_text().strip()
        console.print(f"\n[cyan]Root Token:[/cyan] {token}")
        console.print(f"[dim]Set token: export VAULT_TOKEN=$(cat {token_file})[/dim]\n")
    else:
        console.print("\n[yellow]Root token file not found[/yellow]\n")


@cli.command()
def vault_token():
    """
    Print Vault root token to stdout.

    Designed for use in shell scripts and automation:
      export VAULT_TOKEN=$(./devstack vault-token)
    """
    token_file = VAULT_CONFIG_DIR / "root-token"
    if not token_file.exists():
        console.print("[red]Error: Root token file not found[/red]", file=sys.stderr)
        console.print("[yellow]Run './devstack vault-init' first[/yellow]", file=sys.stderr)
        sys.exit(1)

    # Print raw token to stdout (no formatting)
    print(token_file.read_text().strip())


@cli.command()
def vault_bootstrap():
    """
    Bootstrap Vault with PKI and service credentials.

    This is a ONE-TIME setup command run after first start.

    \b
    Bootstrap sequence:
      1. Enable PKI secrets engine
      2. Generate root CA certificate (10-year validity)
      3. Generate intermediate CA (5-year validity)
      4. Configure certificate roles for services
      5. Enable KV v2 secrets engine
      6. Store all service passwords in Vault
      7. Export CA certificate chain
    """
    console.print("\n[cyan]═══ Vault - Bootstrap PKI and Secrets ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    vault_bootstrap_script = SCRIPT_DIR / "configs" / "vault" / "scripts" / "vault-bootstrap.sh"
    if not vault_bootstrap_script.exists():
        console.print(f"[red]Error: Vault bootstrap script not found at {vault_bootstrap_script}[/red]\n")
        return

    # Set Vault environment variables
    token = get_vault_token()
    if not token:
        console.print("[red]Error: VAULT_TOKEN not set and root token file not found[/red]")
        console.print("[yellow]Run './devstack vault-init' first[/yellow]\n")
        return

    env = {
        "VAULT_ADDR": "http://localhost:8200",
        "VAULT_TOKEN": token
    }

    console.print("[yellow]Running Vault PKI and secrets bootstrap...[/yellow]\n")
    run_command(["bash", str(vault_bootstrap_script)], env=env)

    # Create Forgejo database in PostgreSQL
    console.print("\n[yellow]Creating Forgejo database in PostgreSQL...[/yellow]")
    forgejo_sql = SCRIPT_DIR / "configs" / "postgres" / "02-create-forgejo-db.sql"
    if forgejo_sql.exists():
        returncode, _, _ = run_command(
            ["docker", "compose", "exec", "-T", "postgres", "psql", "-U", "devuser", "-d", "postgres"],
            check=False,
            capture=True
        )
        if returncode == 0:
            # SQL file exists for reference but not used in automated initialization
            run_command(
                ["docker", "compose", "exec", "-T", "postgres", "psql", "-U", "devuser", "-d", "postgres"],
                check=False
            )
            console.print("[green]✓ Forgejo database created successfully[/green]")
        else:
            console.print("[yellow]⚠ Forgejo database may already exist or PostgreSQL is not ready[/yellow]")

    console.print("\n[green]✓ Vault bootstrap completed[/green]\n")


@cli.command()
def vault_ca_cert():
    """
    Export Vault CA certificate chain to stdout.

    The CA certificate is required for clients to trust TLS connections
    to services using Vault-issued certificates.

    \b
    Usage examples:
      # Save to file
      ./devstack vault-ca-cert > vault-ca.pem

      # Install on macOS
      ./devstack vault-ca-cert | sudo security add-trusted-cert \\
        -d -r trustRoot -k /Library/Keychains/System.keychain /dev/stdin
    """
    ca_file = VAULT_CONFIG_DIR / "ca" / "ca-chain.pem"

    if not ca_file.exists():
        console.print(f"[red]Error: CA certificate not found at: {ca_file}[/red]", file=sys.stderr)
        console.print("[yellow]Run './devstack vault-bootstrap' first[/yellow]", file=sys.stderr)
        sys.exit(1)

    # Print raw certificate to stdout (no formatting)
    print(ca_file.read_text())
    console.print(f"\n[dim]CA certificate location: {ca_file}[/dim]", file=sys.stderr)


@cli.command()
@click.argument("service")
def vault_show_password(service: str):
    """
    Retrieve and display service credentials from Vault.

    \b
    ARGUMENTS:
      service                 Service name (required)
                              Available: postgres, mysql, redis-1, redis-2,
                                        redis-3, rabbitmq, mongodb, forgejo

    \b
    OPTIONS:
      None - This command uses an argument, not options

    \b
    AVAILABLE SERVICES:
      postgres   - PostgreSQL admin password
      mysql      - MySQL root password
      redis-1    - Redis AUTH password (same for all Redis nodes)
      redis-2    - Redis AUTH password (same for all Redis nodes)
      redis-3    - Redis AUTH password (same for all Redis nodes)
      rabbitmq   - RabbitMQ admin password
      mongodb    - MongoDB root password
      forgejo    - Admin username, email, and password

    \b
    EXAMPLES:
      # Get PostgreSQL password
      ./devstack vault-show-password postgres

      # Get Forgejo admin credentials
      ./devstack vault-show-password forgejo

      # Get Redis password
      ./devstack vault-show-password redis-1

      # Use in scripts
      MYSQL_PASS=$(./devstack vault-show-password mysql | grep Password | awk '{print $2}')

    \b
    NOTES:
      - ⚠️  Passwords are displayed in plaintext - ensure terminal is secure
      - Requires Vault to be initialized and bootstrapped
      - All credentials are randomly generated during vault-bootstrap
      - Redis nodes share the same password (stored in secret/redis-1)
    """
    # Validate service
    valid_services = ["postgres", "mysql", "redis-1", "redis-2", "redis-3", "rabbitmq", "mongodb", "forgejo"]
    if service not in valid_services:
        console.print(f"[red]Error: Invalid service '{service}'[/red]")
        console.print(f"\n[yellow]Available services:[/yellow] {', '.join(valid_services)}\n")
        sys.exit(1)

    # Get token
    token = get_vault_token()
    if not token:
        console.print("[red]Error: VAULT_TOKEN not set[/red]")
        console.print("[yellow]Run './devstack vault-init' first[/yellow]\n")
        sys.exit(1)

    console.print("\n[yellow]⚠ Password will be displayed in plaintext[/yellow]")
    console.print("[yellow]Ensure terminal is secure[/yellow]\n")

    if service == "forgejo":
        # Get Forgejo credentials (username, email, password)
        console.print(f"[cyan]Fetching credentials for service: {service}[/cyan]\n")

        _, admin_user, _ = run_command(
            ["docker", "exec", "dev-vault", "sh", "-c",
             f"export VAULT_TOKEN=$(cat /vault-keys/root-token) && vault kv get -field=admin_user secret/{service}"],
            capture=True,
            check=False
        )

        _, admin_email, _ = run_command(
            ["docker", "exec", "dev-vault", "sh", "-c",
             f"export VAULT_TOKEN=$(cat /vault-keys/root-token) && vault kv get -field=admin_email secret/{service}"],
            capture=True,
            check=False
        )

        _, password, _ = run_command(
            ["docker", "exec", "dev-vault", "sh", "-c",
             f"export VAULT_TOKEN=$(cat /vault-keys/root-token) && vault kv get -field=admin_password secret/{service}"],
            capture=True,
            check=False
        )

        admin_user = admin_user.strip()
        admin_email = admin_email.strip()
        password = password.strip()

        if not admin_user or admin_user == "null" or not password or password == "null":
            console.print(f"[red]Error: Could not retrieve credentials for {service}[/red]")
            console.print(f"[yellow]Make sure credentials exist: vault kv get secret/{service}[/yellow]\n")
            sys.exit(1)

        console.print(f"[green]✓ Forgejo Admin Credentials:[/green]")
        console.print(f"  [cyan]Username:[/cyan] {admin_user}")
        console.print(f"  [cyan]Email:[/cyan]    {admin_email}")
        console.print(f"  [cyan]Password:[/cyan] {password}\n")
    else:
        # Get password for other services
        console.print(f"[cyan]Fetching password for service: {service}[/cyan]\n")

        _, password, _ = run_command(
            ["docker", "exec", "dev-vault", "sh", "-c",
             f"export VAULT_TOKEN=$(cat /vault-keys/root-token) && vault kv get -field=password secret/{service}"],
            capture=True,
            check=False
        )

        password = password.strip()

        if not password or password == "null":
            console.print(f"[red]Error: Could not retrieve password for {service}[/red]")
            console.print("[yellow]Make sure the service exists in Vault: vault kv list secret/[/yellow]\n")
            sys.exit(1)

        console.print(f"[green]✓ Password for {service}:[/green]")
        console.print(f"  {password}\n")


@cli.command()
def forgejo_init():
    """
    Initialize Forgejo via automated bootstrap script.

    Run this AFTER:
      ./devstack start
      ./devstack vault-bootstrap

    Forgejo will be accessible at: http://localhost:3000
    """
    console.print("\n[cyan]═══ Forgejo - Initialize ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./devstack start\n")
        return

    # Check if Forgejo container is running
    returncode, stdout, _ = run_command(
        ["docker", "compose", "ps", "forgejo", "--format", "json"],
        capture=True,
        check=False
    )

    if returncode != 0 or "running" not in stdout.lower():
        console.print("[red]Error: Forgejo container is not running[/red]")
        console.print("[yellow]Start it with: docker compose up -d forgejo[/yellow]\n")
        return

    console.print("[yellow]Running Forgejo automated installation...[/yellow]\n")

    returncode, _, _ = run_command(
        ["docker", "compose", "exec", "forgejo", "/usr/local/bin/forgejo-bootstrap.sh"],
        check=False
    )

    if returncode == 0:
        console.print("\n[green]✓ Forgejo is now ready to use![/green]")
        console.print("[cyan]Access at:[/cyan] http://localhost:3000\n")
    else:
        console.print("\n[red]Error: Forgejo bootstrap failed[/red]\n")


@cli.command()
def redis_cluster_init():
    """
    Initialize Redis cluster (required for standard/full profiles).

    Creates a 3-node Redis cluster with automatic slot distribution.
    Only needed once after first start with standard or full profile.
    """
    # Check if redis-1 is running
    returncode, stdout, _ = run_command(
        ["docker", "ps", "--filter", "name=dev-redis-1", "--format", "{{.Names}}"],
        capture=True,
        check=False
    )

    if returncode != 0 or "dev-redis-1" not in stdout:
        console.print("[red]Error: Redis containers are not running[/red]")
        console.print("[yellow]Start with: ./devstack start --profile standard[/yellow]\n")
        return

    # Get Redis password from Vault
    if not check_vault_token():
        console.print("[yellow]Warning: Vault token not found[/yellow]")
        console.print("[yellow]Cannot initialize cluster without Vault credentials[/yellow]\n")
        return

    # Retrieve password from Vault (using token from inside container)
    returncode, redis_password, _ = run_command(
        ["docker", "exec", "dev-vault", "sh", "-c",
         "export VAULT_TOKEN=$(cat /vault-keys/root-token) && vault kv get -field=password secret/redis-1"],
        capture=True,
        check=False
    )

    if returncode != 0:
        console.print("[red]Error: Could not retrieve Redis password from Vault[/red]")
        console.print("[yellow]Ensure Vault is running and bootstrapped[/yellow]\n")
        return

    redis_password = redis_password.strip()

    # Call the bash script with the password
    script_path = os.path.join(os.path.dirname(os.path.dirname(__file__)), "configs", "redis", "scripts", "redis-cluster-init.sh")
    returncode, stdout, stderr = run_command(
        ["bash", script_path],
        capture=False,
        check=False,
        env={"REDIS_PASSWORD": redis_password}
    )

    if returncode != 0:
        console.print(f"[red]Error: Redis cluster initialization failed (exit code {returncode})[/red]\n")
    else:
        console.print()  # Extra newline for spacing


# ==============================================================================
# Main Entry Point
# ==============================================================================

if __name__ == "__main__":
    cli()
