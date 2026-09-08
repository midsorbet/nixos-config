"""Manage a leased Cloudflare Tunnel connector through native launchd tools."""

import argparse
import contextlib
import fcntl
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

DEFAULT_TTL_SECONDS = 8 * 60 * 60
MAX_TTL_SECONDS = 12 * 60 * 60
READINESS_TIMEOUT_SECONDS = 30
LAUNCHD_LABEL = "org.nixos.herdr-relay"


class RelayError(Exception):
    """Report a safe, actionable relay lifecycle error to the CLI user."""


def relay_service() -> str:
    """Return the current user's GUI launchd service target."""
    return f"gui/{os.getuid()}/{LAUNCHD_LABEL}"


@contextlib.contextmanager
def relay_lock(state: Path):
    """Exclude concurrent relay mutations with an operating-system file lock."""
    with (state / "operation.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RelayError("Another relay operation is running") from None
        yield


def parse_relay_ttl(value: str) -> int:
    """Parse a positive lease duration no longer than twelve hours."""
    match = re.fullmatch(r"([1-9][0-9]{0,4})([smh]?)", value)
    if not match:
        raise argparse.ArgumentTypeError("Use a positive duration such as 8h or 30m")
    seconds = int(match[1]) * {"": 1, "s": 1, "m": 60, "h": 3600}[match[2]]
    if seconds > MAX_TTL_SECONDS:
        raise argparse.ArgumentTypeError("Relay leases cannot exceed 12 hours")
    return seconds


def lease_path(state: Path) -> Path:
    """Return the single authoritative local relay lease path."""
    return state / "lease.json"


def read_relay_expiry(state: Path) -> int | None:
    """Read the lease expiry as Unix seconds, or None when no lease exists."""
    path = lease_path(state)
    if not path.exists():
        return None
    try:
        lease = json.loads(path.read_text())
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise RelayError("Local relay lease is invalid") from None
    expiry = lease.get("expiresAt") if isinstance(lease, dict) else None
    if type(expiry) is not int:
        raise RelayError("Local relay lease expiry is invalid")
    return expiry


def write_relay_lease(state: Path, expiry: int) -> None:
    """Atomically publish a complete lease containing its Unix expiry time."""
    descriptor, temporary_name = tempfile.mkstemp(prefix="lease.", dir=state)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump({"expiresAt": expiry}, output, separators=(",", ":"))
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, lease_path(state))
    finally:
        temporary.unlink(missing_ok=True)


def invalidate_relay_lease(state: Path) -> None:
    """Remove lease authority before any connector stop is requested."""
    lease_path(state).unlink(missing_ok=True)


def signal_relay_connector() -> None:
    """Signal the launchd-owned timeout process and its connector child to terminate."""
    result = subprocess.run(
        ["launchctl", "kill", "SIGTERM", relay_service()],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    # launchctl uses ESRCH (3) when the loaded job has no running process.
    if result.returncode not in (0, 3):
        raise RelayError("Could not stop the relay connector through launchd")


def stop_relay(config: dict[str, object], state: Path) -> dict[str, str]:
    """Invalidate the current lease before stopping the GUI launchd connector job."""
    invalidate_relay_lease(state)
    signal_relay_connector()
    deadline = time.monotonic() + 10
    while metrics_endpoint_occupied(str(config["metricsAddress"])):
        if time.monotonic() >= deadline:
            raise RelayError("Relay connector remained reachable after stop")
        time.sleep(0.1)
    return {"status": "stopped"}


def split_metrics_address(address: str) -> tuple[str, int]:
    """Split a cloudflared metrics listen address into its socket host and port."""
    if address.startswith("["):
        closing = address.find("]")
        if closing < 0 or address[closing + 1 : closing + 2] != ":":
            raise RelayError("Relay metrics address is invalid")
        host, port_text = address[1:closing], address[closing + 2 :]
    else:
        host, separator, port_text = address.rpartition(":")
        if not separator:
            raise RelayError("Relay metrics address is invalid")
    try:
        port = int(port_text)
    except ValueError:
        raise RelayError("Relay metrics address is invalid") from None
    if not host or not 1 <= port <= 65535:
        raise RelayError("Relay metrics address is invalid")
    return host, port


def metrics_endpoint_occupied(address: str) -> bool:
    """Detect any listener that could impersonate the connector readiness endpoint."""
    host, port = split_metrics_address(address)
    try:
        with socket.create_connection((host, port), timeout=0.25):
            return True
    except OSError:
        return False


def cloudflared_ready(address: str) -> bool:
    """Return whether cloudflared's local readiness endpoint currently answers HTTP 200."""
    host, port = split_metrics_address(address)
    url_host = f"[{host}]" if ":" in host else host
    try:
        with urllib.request.urlopen(
            f"http://{url_host}:{port}/ready", timeout=0.5
        ) as response:
            return response.status == 200
    except (OSError, urllib.error.URLError):
        return False


def start_relay(config: dict[str, object], state: Path, seconds: int) -> dict[str, object]:
    """Start one non-extendable lease and wait for this connector to become ready."""
    now = int(time.time())
    existing_expiry = read_relay_expiry(state)
    if existing_expiry is not None and existing_expiry > now:
        raise RelayError("An active relay lease already exists; stop it before starting")
    if existing_expiry is not None:
        invalidate_relay_lease(state)
        signal_relay_connector()

    metrics_address = str(config["metricsAddress"])
    if metrics_endpoint_occupied(metrics_address):
        raise RelayError("Relay metrics endpoint is already occupied")

    expiry = now + seconds
    write_relay_lease(state, expiry)
    try:
        subprocess.run(
            ["launchctl", "kickstart", "-k", relay_service()],
            check=True,
        )
        readiness_deadline = min(expiry, now + READINESS_TIMEOUT_SECONDS)
        while int(time.time()) < readiness_deadline:
            if cloudflared_ready(metrics_address):
                return {
                    "status": "ready",
                    "hostname": config["hostname"],
                    "expiresAt": expiry,
                }
            time.sleep(0.25)
        raise RelayError("Cloudflare relay did not become ready before the startup deadline")
    except BaseException:
        invalidate_relay_lease(state)
        try:
            signal_relay_connector()
        except (OSError, RelayError):
            print("herdr-relay: cleanup could not stop the connector", file=sys.stderr)
        raise


def relay_status(config: dict[str, object], state: Path) -> dict[str, object]:
    """Report stopped, expired, connecting, or ready from the lease and /ready."""
    expiry = read_relay_expiry(state)
    if expiry is None:
        return {"status": "stopped", "hostname": config["hostname"]}
    result: dict[str, object] = {
        "status": "expired" if expiry <= int(time.time()) else "connecting",
        "hostname": config["hostname"],
        "expiresAt": expiry,
    }
    if result["status"] == "connecting" and cloudflared_ready(
        str(config["metricsAddress"])
    ):
        result["status"] = "ready"
    return result


def connect_relay(config: dict[str, object], state: Path) -> int:
    """Exec cloudflared beneath native timeout for exactly the lease time remaining."""
    expiry = read_relay_expiry(state)
    if expiry is None:
        return 0
    remaining = expiry - int(time.time())
    if remaining <= 0:
        return 0
    arguments = [
        "timeout",
        "--foreground",
        "--signal=TERM",
        "--kill-after=5s",
        str(remaining),
        "cloudflared",
        "tunnel",
        "--config",
        str(config["tunnelConfig"]),
        "--no-autoupdate",
        "--metrics",
        str(config["metricsAddress"]),
        "run",
        str(config["tunnelId"]),
    ]
    os.execvp(arguments[0], arguments)
    return 1


def load_relay_config(path: str) -> tuple[dict[str, object], Path]:
    """Load the Cloudflare relay config and secure its user-owned state directory."""
    config = json.loads(Path(path).read_text())
    required = ("stateDirectory", "hostname", "tunnelId", "tunnelConfig")
    if not isinstance(config, dict) or any(
        not isinstance(config.get(key), str) or not config[key] for key in required
    ):
        raise RelayError("Relay configuration is missing a required string value")
    config.setdefault("metricsAddress", "127.0.0.1:17478")
    if not isinstance(config["metricsAddress"], str):
        raise RelayError("Relay metrics address is invalid")
    split_metrics_address(config["metricsAddress"])

    state = Path(config["stateDirectory"])
    if state.is_symlink():
        raise RelayError(
            "Relay state directory must be owned by the current user and not a symlink"
        )
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    if state.stat().st_uid != os.getuid():
        raise RelayError(
            "Relay state directory must be owned by the current user and not a symlink"
        )
    state.chmod(0o700)
    return config, state


def main() -> int:
    """Run the herdr-relay command-line lifecycle interface."""
    parser = argparse.ArgumentParser(
        prog="herdr-relay",
        description="Manage an on-demand Cloudflare Tunnel connector",
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("HERDR_RELAY_CONFIG", "/etc/herdr-relay.json"),
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("start", help="start a leased Cloudflare connector").add_argument(
        "--ttl", type=parse_relay_ttl, default=DEFAULT_TTL_SECONDS
    )
    commands.add_parser("stop", help="stop the Cloudflare connector")
    commands.add_parser("status", help="show the local connector lease and readiness")
    commands.add_parser("connect", help="run cloudflared under launchd for the lease")
    arguments = parser.parse_args()

    os.umask(0o077)
    config, state = load_relay_config(arguments.config)
    if arguments.command == "connect":
        return connect_relay(config, state)
    if arguments.command == "status":
        result = relay_status(config, state)
    else:
        with relay_lock(state):
            if arguments.command == "start":
                result = start_relay(config, state, arguments.ttl)
            else:
                result = stop_relay(config, state)
    print(json.dumps(result, separators=(",", ":")))
    return 0


def terminate_relay(_signal: int, _frame: object) -> None:
    """Turn service-manager signals into startup unwinding that invalidates the lease."""
    raise KeyboardInterrupt


def install_signal_handlers() -> None:
    """Ensure interruption unwinds a start operation through its cleanup path."""
    signal.signal(signal.SIGTERM, terminate_relay)
    signal.signal(signal.SIGHUP, terminate_relay)


if __name__ == "__main__":
    install_signal_handlers()
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("herdr-relay: interrupted; relay lease was invalidated", file=sys.stderr)
        sys.exit(130)
    except (RelayError, OSError, ValueError, KeyError, subprocess.SubprocessError):
        error = sys.exception()
        message = str(error) if isinstance(error, RelayError) else "configuration or local I/O failed"
        print("herdr-relay: " + message, file=sys.stderr)
        sys.exit(1)
