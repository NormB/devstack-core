"""
DevStack Core Utility Functions
===============================

Core utility functions for command execution, configuration loading,
and common operations used throughout the DevStack management scripts.

Functions:
- run_command: Execute shell commands with environment handling
- load_profiles_config: Load and parse profiles.yaml
- load_profile_env: Load environment from profile .env files
- get_profile_services: Get service list for a profile
- check_colima_status: Check if Colima VM is running
- calculate_file_checksum: Calculate SHA256 checksum of a file
"""

from __future__ import annotations

import os
import sys
import subprocess
import hashlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple, Any

try:
    import yaml
    from rich.console import Console
    from dotenv import dotenv_values
except ImportError as e:
    sys.stderr.write(f"Error: Missing required dependency: {e}\n")
    sys.stderr.write("Install with: uv pip install -r scripts/requirements.txt\n")
    sys.exit(1)

# Rich console for output
console = Console()

# Path configuration
SCRIPT_DIR = Path(__file__).parent.parent.parent.resolve()  # Project root
PROFILES_FILE = SCRIPT_DIR / "profiles.yaml"
COMPOSE_FILE = SCRIPT_DIR / "docker-compose.yml"
ENV_FILE = SCRIPT_DIR / ".env"
PROFILES_DIR = SCRIPT_DIR / "configs" / "profiles"
VAULT_CONFIG_DIR = Path.home() / ".config" / "vault"

# Colima defaults
COLIMA_PROFILE = os.getenv("COLIMA_PROFILE", "default")
COLIMA_CPU = os.getenv("COLIMA_CPU", "4")
COLIMA_MEMORY = os.getenv("COLIMA_MEMORY", "8")
COLIMA_DISK = os.getenv("COLIMA_DISK", "60")


def run_command(
    cmd: List[str],
    check: bool = True,
    capture: bool = False,
    env: Optional[Dict[str, str]] = None,
    input_data: Optional[str] = None,
    cwd: Optional[Path] = None
) -> Tuple[int, str, str]:
    """
    Run a shell command with optional environment variables.

    Args:
        cmd: Command and arguments as list
        check: Raise error if command fails (default: True)
        capture: Capture stdout/stderr (default: False)
        env: Additional environment variables to merge
        input_data: Input data to send to stdin
        cwd: Working directory for command

    Returns:
        Tuple of (returncode, stdout, stderr)

    Raises:
        SystemExit: If check=True and command fails
    """
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
                input=input_data,
                cwd=cwd
            )
            return result.returncode, result.stdout, result.stderr
        else:
            result = subprocess.run(
                cmd,
                check=check,
                env=cmd_env,
                input=input_data,
                text=True if input_data else False,
                cwd=cwd
            )
            return result.returncode, "", ""
    except subprocess.CalledProcessError as e:
        if check:
            console.print(f"[red]Error running command: {' '.join(cmd)}[/red]")
            console.print(f"[red]Exit code: {e.returncode}[/red]")
            if capture and e.stderr:
                console.print(f"[red]{e.stderr}[/red]")
            sys.exit(e.returncode)
        return e.returncode, getattr(e, 'stdout', '') or '', getattr(e, 'stderr', '') or ''
    except FileNotFoundError:
        console.print(f"[red]Command not found: {cmd[0]}[/red]")
        console.print(f"[yellow]Make sure {cmd[0]} is installed and in your PATH[/yellow]")
        sys.exit(1)


def load_profiles_config() -> Dict[str, Any]:
    """
    Load and parse profiles.yaml configuration.

    Returns:
        Dictionary containing profiles configuration

    Raises:
        SystemExit: If profiles.yaml not found
    """
    if not PROFILES_FILE.exists():
        console.print(f"[red]Error: {PROFILES_FILE} not found[/red]")
        sys.exit(1)

    with open(PROFILES_FILE) as f:
        return yaml.safe_load(f)


def load_profile_env(profile: str) -> Dict[str, str]:
    """
    Load environment variables from a profile .env file.

    Args:
        profile: Profile name (e.g., "standard", "minimal")

    Returns:
        Dictionary of environment variables from profile.env file,
        or empty dict if file doesn't exist
    """
    profile_env_file = PROFILES_DIR / f"{profile}.env"

    if not profile_env_file.exists():
        return {}

    return dotenv_values(profile_env_file)


def get_profile_services(profile: str) -> List[str]:
    """
    Get list of services for a given profile.

    Args:
        profile: Profile name

    Returns:
        List of service names

    Raises:
        SystemExit: If profile not found
    """
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
    """
    Check if Colima VM is running.

    Returns:
        True if Colima is running, False otherwise
    """
    returncode, stdout, stderr = run_command(
        ["colima", "status", "-p", COLIMA_PROFILE],
        check=False,
        capture=True
    )
    output = (stdout + stderr).lower()
    return returncode == 0 and "running" in output


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


def format_size(size_bytes: int) -> str:
    """
    Format byte size to human-readable string.

    Args:
        size_bytes: Size in bytes

    Returns:
        Human-readable size string (e.g., "1.5 GB")
    """
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if size_bytes < 1024:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024
    return f"{size_bytes:.1f} PB"
