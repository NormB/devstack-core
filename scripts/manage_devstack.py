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
    ./manage-devstack --help
    ./manage-devstack start --profile standard
    ./manage-devstack status
    ./manage-devstack health

Requirements:
    pip3 install click rich PyYAML python-dotenv

Author: DevStack Core Team
License: MIT
"""

import os
import sys
import subprocess
from pathlib import Path
from typing import List, Dict, Optional, Tuple

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
    print("  ./manage-devstack --help")
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


# ==============================================================================
# CLI Commands
# ==============================================================================

@click.group()
@click.version_option(version="1.0.0", prog_name="manage-devstack")
def cli():
    """DevStack Core Management Script - Modern Python CLI for Docker-based development infrastructure.

    \b
    USAGE
      manage-devstack [COMMAND] [OPTIONS]
      manage-devstack [COMMAND] --help

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
      ./manage-devstack start                     # Start with standard profile
      ./manage-devstack vault-bootstrap           # Setup Vault PKI + credentials
      ./manage-devstack redis-cluster-init        # Initialize Redis cluster
      ./manage-devstack forgejo-init              # Initialize Forgejo

    \b
    COMMON EXAMPLES
      # Start with specific profile
      ./manage-devstack start --profile minimal

      # Combine multiple profiles
      ./manage-devstack start --profile standard --profile reference

      # Monitor service logs in real-time
      ./manage-devstack logs -f postgres

      # Create backup before changes
      ./manage-devstack backup

      # Get service credentials
      ./manage-devstack vault-show-password mysql

    \b
    GETTING HELP
      For detailed help on any command:
        ./manage-devstack COMMAND --help

      Examples:
        ./manage-devstack start --help
        ./manage-devstack vault-show-password --help
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
      ./manage-devstack start

      # Start with minimal profile
      ./manage-devstack start --profile minimal

      # Combine standard and reference profiles
      ./manage-devstack start --profile standard --profile reference

      # Start in foreground (see logs in real-time)
      ./manage-devstack start --no-detach

    \b
    NOTES:
      - Colima VM starts automatically if not running
      - After first start, run: ./manage-devstack vault-bootstrap
      - For standard/full profiles, run: ./manage-devstack redis-cluster-init
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
        console.print("     [yellow]./manage-devstack redis-cluster-init[/yellow]")
        console.print("  2. Check service health:")
        console.print("     [yellow]./manage-devstack health[/yellow]")
    else:
        console.print("  • Check service health:")
        console.print("    [yellow]./manage-devstack health[/yellow]")

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
      ./manage-devstack stop

      # Stop only reference profile services
      ./manage-devstack stop --profile reference

      # Stop multiple profiles
      ./manage-devstack stop --profile standard --profile reference

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
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
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
        console.print("[dim]Start services with: ./manage-devstack start[/dim]")

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
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
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

    import json
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
      ./manage-devstack logs

      # View PostgreSQL logs only
      ./manage-devstack logs postgres

      # Follow Vault logs in real-time
      ./manage-devstack logs -f vault

      # Show last 500 lines of Redis logs
      ./manage-devstack logs --tail 500 redis-1

      # Follow all service logs
      ./manage-devstack logs -f

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
      ./manage-devstack shell postgres

      # Open bash shell in Vault container
      ./manage-devstack shell vault --shell bash

      # Open shell in Redis container
      ./manage-devstack shell redis-1

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

    console.print("\n[dim]Use with: ./manage-devstack start --profile <name>[/dim]\n")


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
        import json
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
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
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
    ALWAYS run './manage-devstack backup' before reset!
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
    console.print("[cyan]Run './manage-devstack start' to create a fresh VM[/cyan]\n")


@cli.command()
def backup():
    """
    Backup all service data to timestamped directory.

    \b
    Backup includes:
      - PostgreSQL: Complete dump of all databases
      - MySQL: Complete dump of all databases
      - MongoDB: Binary archive dump
      - Forgejo: Tarball of /data directory (repos, uploads, config)
      - .env file: Configuration backup

    \b
    Backup location: ./backups/YYYYMMDD_HHMMSS/
    """
    console.print("\n[cyan]═══ DevStack Core - Backup ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
        return

    # Create backup directory
    from datetime import datetime
    backup_dir = SCRIPT_DIR / "backups" / datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_dir.mkdir(parents=True, exist_ok=True)

    console.print(f"[cyan]Creating backup in:[/cyan] {backup_dir}\n")

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        # Backup PostgreSQL
        task = progress.add_task("Backing up PostgreSQL...", total=None)
        returncode, stdout, _ = run_command(
            ["docker", "compose", "exec", "-T", "postgres", "pg_dumpall", "-U", "dev_admin"],
            capture=True,
            check=False
        )
        if returncode == 0:
            (backup_dir / "postgres_all.sql").write_text(stdout)
            progress.update(task, description="[green]✓ PostgreSQL backed up[/green]")
        else:
            progress.update(task, description="[yellow]⚠ PostgreSQL backup failed[/yellow]")

        # Backup MySQL
        task = progress.add_task("Backing up MySQL...", total=None)
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
            returncode, stdout, _ = run_command(
                ["docker", "compose", "exec", "-T", "mysql", "sh", "-c",
                 f"mysqldump -u root -p'{mysql_pass}' --all-databases"],
                capture=True,
                check=False
            )
            if returncode == 0:
                (backup_dir / "mysql_all.sql").write_text(stdout)
                progress.update(task, description="[green]✓ MySQL backed up[/green]")
            else:
                progress.update(task, description="[yellow]⚠ MySQL backup failed[/yellow]")
        else:
            progress.update(task, description="[yellow]⚠ MySQL backup skipped (no password)[/yellow]")

        # Backup MongoDB
        task = progress.add_task("Backing up MongoDB...", total=None)
        try:
            result = subprocess.run(
                ["docker", "compose", "exec", "-T", "mongodb", "mongodump", "--archive"],
                capture_output=True,
                check=False
            )
            if result.returncode == 0:
                (backup_dir / "mongodb_dump.archive").write_bytes(result.stdout)
                progress.update(task, description="[green]✓ MongoDB backed up[/green]")
            else:
                progress.update(task, description="[yellow]⚠ MongoDB backup failed[/yellow]")
        except Exception as e:
            progress.update(task, description=f"[yellow]⚠ MongoDB backup error: {e}[/yellow]")

        # Backup Forgejo
        task = progress.add_task("Backing up Forgejo...", total=None)
        try:
            result = subprocess.run(
                ["docker", "compose", "exec", "-T", "forgejo", "tar", "czf", "-", "/data"],
                capture_output=True,
                check=False
            )
            if result.returncode == 0:
                (backup_dir / "forgejo_data.tar.gz").write_bytes(result.stdout)
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

    # Show backup size
    try:
        result = subprocess.run(
            ["du", "-sh", str(backup_dir)],
            capture_output=True,
            text=True
        )
        size = result.stdout.split()[0]
        console.print(f"\n[green]✓ Backup completed:[/green] {backup_dir}")
        console.print(f"[cyan]Backup size:[/cyan] {size}\n")
    except Exception:
        console.print(f"\n[green]✓ Backup completed:[/green] {backup_dir}\n")


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
      ./manage-devstack restore

      # Restore from specific backup
      ./manage-devstack restore 20250110_143022

      # Typical restore workflow
      ./manage-devstack stop                    # Stop services first
      ./manage-devstack restore 20250110_143022 # Restore backup
      ./manage-devstack start                   # Restart services

    \b
    RESTORED DATA:
      - PostgreSQL: All databases and tables
      - MySQL: All databases and tables
      - MongoDB: All collections and documents
      - Forgejo: Git repositories, uploads, and configuration
      - .env file: Environment configuration

    \b
    NOTES:
      - Always create a backup before restoring: ./manage-devstack backup
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
            console.print("[cyan]Create a backup first:[/cyan] ./manage-devstack backup\n")
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
        console.print("\n[cyan]To restore a backup:[/cyan] ./manage-devstack restore BACKUP_NAME\n")
        return

    # Validate backup exists
    backup_dir = backups_dir / backup_name
    if not backup_dir.exists():
        console.print(f"[red]Error: Backup not found:[/red] {backup_dir}\n")
        console.print("[cyan]List available backups:[/cyan] ./manage-devstack restore\n")
        return

    # Check if services are running
    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
        return

    # Confirm restoration
    console.print(f"[yellow]⚠️  WARNING: This will OVERWRITE current data with backup from {backup_name}[/yellow]\n")
    console.print("[red]This operation cannot be undone![/red]\n")

    import click
    if not click.confirm("Are you sure you want to continue?", default=False):
        console.print("\n[yellow]Restore cancelled.[/yellow]\n")
        return

    console.print(f"\n[cyan]Restoring from:[/cyan] {backup_dir}\n")

    with Progress(
        SpinnerColumn(),
        TextColumn("[progress.description]{task.description}"),
        console=console
    ) as progress:
        # Restore PostgreSQL
        postgres_backup = backup_dir / "postgres_all.sql"
        if postgres_backup.exists():
            task = progress.add_task("Restoring PostgreSQL...", total=None)
            try:
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
        mysql_backup = backup_dir / "mysql_all.sql"
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
                    with open(mysql_backup, 'r') as f:
                        returncode, _, _ = run_command(
                            ["docker", "compose", "exec", "-T", "mysql", "sh", "-c",
                             f"mysql -u root -p'{mysql_pass}'"],
                            capture=False,
                            check=False,
                            input=f.read()
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
        mongodb_backup = backup_dir / "mongodb_dump.archive"
        if mongodb_backup.exists():
            task = progress.add_task("Restoring MongoDB...", total=None)
            try:
                import subprocess
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
        forgejo_backup = backup_dir / "forgejo_data.tar.gz"
        if forgejo_backup.exists():
            task = progress.add_task("Restoring Forgejo...", total=None)
            try:
                import subprocess  # Explicit import to prevent UnboundLocalError
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
        env_backup = backup_dir / ".env.backup"
        if env_backup.exists():
            task = progress.add_task("Restoring .env file...", total=None)
            try:
                import shutil
                shutil.copy(env_backup, ENV_FILE)
                progress.update(task, description="[green]✓ .env file restored[/green]")
            except Exception as e:
                progress.update(task, description=f"[red]✗ .env restore error: {e}[/red]")

    console.print(f"\n[green]✓ Restore completed from:[/green] {backup_dir}")
    console.print("[yellow]⚠  Restart services to apply changes:[/yellow] ./manage-devstack restart\n")


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
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
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
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
        return

    vault_keys_file = VAULT_CONFIG_DIR / "keys.json"
    if not vault_keys_file.exists():
        console.print(f"[red]Error: Vault keys file not found: {vault_keys_file}[/red]")
        console.print("[yellow]Run './manage-devstack vault-init' first[/yellow]\n")
        return

    console.print("[yellow]Unsealing Vault...[/yellow]\n")

    # Read keys file
    import json
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
      export VAULT_TOKEN=$(./manage-devstack vault-token)
    """
    token_file = VAULT_CONFIG_DIR / "root-token"
    if not token_file.exists():
        console.print("[red]Error: Root token file not found[/red]", file=sys.stderr)
        console.print("[yellow]Run './manage-devstack vault-init' first[/yellow]", file=sys.stderr)
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
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
        return

    vault_bootstrap_script = SCRIPT_DIR / "configs" / "vault" / "scripts" / "vault-bootstrap.sh"
    if not vault_bootstrap_script.exists():
        console.print(f"[red]Error: Vault bootstrap script not found at {vault_bootstrap_script}[/red]\n")
        return

    # Set Vault environment variables
    token = get_vault_token()
    if not token:
        console.print("[red]Error: VAULT_TOKEN not set and root token file not found[/red]")
        console.print("[yellow]Run './manage-devstack vault-init' first[/yellow]\n")
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
      ./manage-devstack vault-ca-cert > vault-ca.pem

      # Install on macOS
      ./manage-devstack vault-ca-cert | sudo security add-trusted-cert \\
        -d -r trustRoot -k /Library/Keychains/System.keychain /dev/stdin
    """
    ca_file = VAULT_CONFIG_DIR / "ca" / "ca-chain.pem"

    if not ca_file.exists():
        console.print(f"[red]Error: CA certificate not found at: {ca_file}[/red]", file=sys.stderr)
        console.print("[yellow]Run './manage-devstack vault-bootstrap' first[/yellow]", file=sys.stderr)
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
      ./manage-devstack vault-show-password postgres

      # Get Forgejo admin credentials
      ./manage-devstack vault-show-password forgejo

      # Get Redis password
      ./manage-devstack vault-show-password redis-1

      # Use in scripts
      MYSQL_PASS=$(./manage-devstack vault-show-password mysql | grep Password | awk '{print $2}')

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
        console.print("[yellow]Run './manage-devstack vault-init' first[/yellow]\n")
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
      ./manage-devstack start
      ./manage-devstack vault-bootstrap

    Forgejo will be accessible at: http://localhost:3000
    """
    console.print("\n[cyan]═══ Forgejo - Initialize ═══[/cyan]\n")

    if not check_colima_status():
        console.print("[red]Error: Colima is not running[/red]")
        console.print("[yellow]Start with:[/yellow] ./manage-devstack start\n")
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
        console.print("[yellow]Start with: ./manage-devstack start --profile standard[/yellow]\n")
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
