"""Coordinate hcloud, frp and native service managers for the ephemeral Hooh relay."""

import argparse
import base64
import binascii
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
from pathlib import Path

from hcloud_relay import (
    HcloudRelay,
    OWNER_SELECTOR,
    SERVER_ROLES,
    RelayError,
    is_relay_server,
    one_relay_resource,
    refuse_existing_hooh,
    relay_command,
    relay_expiry,
    relay_network,
    write_relay_userdata,
)


def relay_service():
    return f"gui/{os.getuid()}/org.nixos.herdr-relay"


@contextlib.contextmanager
def relay_lock(state):
    """Use an OS lock, not PID files or a second process supervisor."""
    with (state / "operation.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RelayError("Another relay operation is running") from None
        yield


def stop_frp(state):
    """Invalidate the lease before signaling launchd, so it cannot reconnect after stop."""
    (state / "lease.json").unlink(missing_ok=True)
    if sys.platform == "darwin":
        registered = (
            subprocess.run(
                ["launchctl", "print", relay_service()], capture_output=True
            ).returncode
            == 0
        )
        if registered:
            relay_command(["launchctl", "stop", "org.nixos.herdr-relay"])


def connect_frp(config, state):
    """launchd starts frpc; frp handles reconnects and GNU timeout enforces the lease."""
    lease = state / "lease.json"
    if not lease.exists():
        return 0
    expiry = json.loads(lease.read_text())["expiresAt"]
    if type(expiry) is not int:
        raise RelayError("Local relay lease expiry is invalid")
    remaining = expiry - int(time.time())
    if remaining <= 0:
        return 0
    result = subprocess.run(
        [
            "timeout",
            "--foreground",
            "--signal=TERM",
            "--kill-after=5s",
            str(remaining),
            "frpc",
            "-c",
            config["frpcConfig"],
        ]
    ).returncode
    return 0 if result in (124, 137) else result


def parse_relay_ttl(value):
    """Accept positive seconds, minutes or hours, with a twelve-hour upper bound."""
    match = re.fullmatch(r"([1-9][0-9]{0,4})([smh]?)", value)
    if not match:
        raise argparse.ArgumentTypeError("Use a positive duration such as 8h or 30m")
    seconds = int(match[1]) * {"": 1, "s": 1, "m": 60, "h": 3600}[match[2]]
    if seconds > 43200:
        raise argparse.ArgumentTypeError("Relay leases cannot exceed 12 hours")
    return seconds


def mini_host_key_identity(config):
    """Validate one canonical Ed25519 public key before creating a paid server."""
    path = Path(config["miniHostPublicKeyFile"])
    if not path.is_file():
        raise RelayError("Mini's SSH host public key is missing")
    try:
        contents = path.read_text()
    except (OSError, UnicodeError):
        raise RelayError(
            "Mini's SSH host public key is malformed; expected one ssh-ed25519 public key"
        ) from None
    lines = [
        line.strip()
        for line in contents.splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]
    if len(lines) != 1:
        raise RelayError(
            "Mini's SSH host public key is malformed; expected one ssh-ed25519 public key"
        )
    fields = lines[0].split()
    if len(fields) < 2 or fields[0] != "ssh-ed25519":
        raise RelayError(
            "Mini's SSH host public key is malformed; expected one ssh-ed25519 public key"
        )
    encoded = fields[1]
    try:
        blob = base64.b64decode(encoded, validate=True)
        if base64.b64encode(blob).decode("ascii") != encoded:
            raise ValueError
        algorithm_size = int.from_bytes(blob[0:4], "big")
        algorithm_end = 4 + algorithm_size
        key_size = int.from_bytes(blob[algorithm_end : algorithm_end + 4], "big")
        key_start = algorithm_end + 4
        if (
            blob[4:algorithm_end] != b"ssh-ed25519"
            or key_size != 32
            or key_start + key_size != len(blob)
        ):
            raise ValueError
    except (ValueError, UnicodeError, binascii.Error):
        raise RelayError(
            "Mini's SSH host public key is malformed; expected one ssh-ed25519 public key"
        ) from None
    return fields[:2]


def verify_mini_endpoint(config, address, expiry):
    """Read the real forwarded SSH host key; a listening TCP port alone is not readiness."""
    expected = mini_host_key_identity(config)
    deadline = min(time.time() + 180, expiry)
    while (remaining := deadline - time.time()) > 0:
        try:
            scan = subprocess.run(
                [
                    "ssh-keyscan",
                    "-T",
                    "3",
                    "-t",
                    "ed25519",
                    "-p",
                    "2222",
                    address,
                ],
                capture_output=True,
                text=True,
                timeout=min(10, remaining),
            )
        except subprocess.TimeoutExpired:
            continue
        keys = [
            fields[1:3]
            for line in scan.stdout.splitlines()
            if line.strip()
            and not line.lstrip().startswith("#")
            and len(fields := line.split()) == 3
        ]
        if expected in keys:
            return
        time.sleep(min(2, max(0, deadline - time.time())))
    raise RelayError(
        "frp did not expose Mini's expected SSH host key before the readiness deadline"
    )


def start_relay(config, state, cloud, seconds):
    """Create one session, ask launchd to start frp, and verify the end-to-end SSH endpoint."""
    if sys.platform != "darwin":
        raise RelayError("start runs on Mini using its launchd agent")
    refuse_existing_hooh(cloud)
    endpoint, firewall = relay_network(cloud)
    if endpoint.get("assignee_id") is not None:
        raise RelayError("The retained IPv4 is already assigned")
    snapshots = cloud.resources(
        "image",
        OWNER_SELECTOR + ",role=relay-image,identity=" + config["imageIdentity"],
        "--type",
        "snapshot",
        "--architecture",
        "x86",
    )
    snapshots = [image for image in snapshots if image["status"] == "available"]
    if not snapshots:
        raise RelayError("No matching frp snapshot exists; run prepare first")
    snapshot = max(snapshots, key=lambda image: image["created"])
    addresses = {
        record[4][0]
        for record in socket.getaddrinfo(
            config["hostname"], 2222, socket.AF_INET, socket.SOCK_STREAM
        )
    }
    if addresses != {endpoint["ip"]}:
        raise RelayError(
            f"Set the DNS-only A record for {config['hostname']} to {endpoint['ip']} before starting"
        )
    relay_command(["launchctl", "print", relay_service()])
    # Verify the local host-key prerequisite before creating anything billable.
    mini_host_key_identity(config)
    expiry = int(time.time()) + seconds
    ready = False
    try:
        with tempfile.TemporaryDirectory(prefix="start-", dir=state) as temporary:
            temporary = Path(temporary)
            userdata = temporary / "user-data"
            write_relay_userdata(userdata, expiry, "session")
            cloud.run(
                "server",
                "create",
                "--name",
                "hooh",
                "--type",
                "cpx11",
                "--location",
                "hil",
                "--image",
                snapshot["id"],
                "--primary-ipv4",
                endpoint["id"],
                "--without-ipv6",
                "--firewall",
                firewall["id"],
                "--label",
                OWNER_SELECTOR,
                "--label",
                "role=session",
                "--label",
                f"expires-at={expiry}",
                "--user-data-from-file",
                userdata,
            )
            server = one_relay_resource(
                [
                    server
                    for server in cloud.owned_servers()
                    if server["name"] == "hooh"
                ],
                "Hooh session server",
            )
            new_lease = temporary / "lease.json"
            new_lease.write_text(
                json.dumps({"serverId": server["id"], "expiresAt": expiry})
            )
            new_lease.replace(state / "lease.json")
            relay_command(["launchctl", "kickstart", "-k", relay_service()])
            verify_mini_endpoint(config, endpoint["ip"], expiry)
            ready = True
            return {
                "status": "ready",
                "serverId": server["id"],
                "hostname": config["hostname"],
                "port": 2222,
                "expiresAt": expiry,
            }
    finally:
        if not ready:
            try:
                stop_frp(state)
            finally:
                for server in cloud.owned_servers():
                    if server["name"] == "hooh" and relay_expiry(server) == expiry:
                        cloud.delete_server(server["id"])


def reap_relay(cloud):
    """A Baymax systemd timer deletes only expired, exactly owned cloud servers."""
    deleted, errors = [], []
    for server in cloud.resources("server"):
        if server.get("name") not in SERVER_ROLES:
            continue
        try:
            if not is_relay_server(server):
                raise RelayError(
                    f"Server {server['id']} has inconsistent ownership labels"
                )
            if relay_expiry(server) <= time.time():
                cloud.delete_server(server["id"])
                deleted.append(server["id"])
        except RelayError as error:
            errors.append(str(error))
    if errors:
        raise RelayError("; ".join(errors))
    return {"deleted": deleted}


def relay_status(cloud):
    return {
        "servers": [
            {
                "id": server["id"],
                "name": server["name"],
                "status": server["status"],
                "expiresAt": relay_expiry(server),
            }
            for server in cloud.owned_servers()
        ],
        "endpoints": [
            {"id": ip["id"], "ip": ip["ip"]} for ip in cloud.resources("primary-ip")
        ],
        "snapshots": [
            {"id": image["id"], "created": image["created"]}
            for image in cloud.resources(
                "image", OWNER_SELECTOR + ",role=relay-image", "--type", "snapshot"
            )
        ],
    }


def main():
    parser = argparse.ArgumentParser(
        prog="herdr-relay",
        description="Use hcloud and frp for the ephemeral Hooh relay",
    )
    parser.add_argument(
        "--config",
        default=os.environ.get("HERDR_RELAY_CONFIG", "/etc/herdr-relay.json"),
    )
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser(
        "prepare", help="create retained infrastructure and a NixOS snapshot"
    ).add_argument("--flake", required=True)
    commands.add_parser("start", help="create a leased VPS and start frp").add_argument(
        "--ttl", type=parse_relay_ttl, default=28800
    )
    for command, help_text in [
        ("stop", "stop frp and delete the session VPS"),
        ("status", "show cloud resources"),
        ("reap", "delete expired VPSs"),
        ("connect", "run frpc under launchd for the current lease"),
    ]:
        commands.add_parser(command, help=help_text)
    arguments = parser.parse_args()
    os.umask(0o077)
    config = json.loads(Path(arguments.config).read_text())
    state = Path(config["stateDirectory"])
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    if state.is_symlink() or state.stat().st_uid != os.getuid():
        raise RelayError(
            "Relay state directory must be owned by the current user and not a symlink"
        )
    state.chmod(0o700)
    if arguments.command == "connect":
        return connect_frp(config, state)
    cloud = HcloudRelay(config["tokenFile"])
    with relay_lock(state):
        if arguments.command == "start":
            result = start_relay(config, state, cloud, arguments.ttl)
        elif arguments.command == "prepare":
            from relay_image import prepare_relay_image

            result = prepare_relay_image(config, state, cloud, arguments.flake)
        elif arguments.command == "stop":
            try:
                stop_frp(state)
            finally:
                for server in cloud.owned_servers():
                    if server["name"] == "hooh":
                        cloud.delete_server(server["id"])
            result = {"status": "stopped", "retainedResourcesStillBilled": True}
        elif arguments.command == "reap":
            result = reap_relay(cloud)
        else:
            result = relay_status(cloud)
    print(json.dumps(result))
    return 0


if __name__ == "__main__":

    def terminate_relay(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, terminate_relay)
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print(
            "herdr-relay: interrupted; inspect status if cloud cleanup could not finish",
            file=sys.stderr,
        )
        sys.exit(130)
    except (RelayError, OSError, ValueError, KeyError) as error:
        message = (
            str(error)
            if isinstance(error, RelayError)
            else "configuration or local I/O failed"
        )
        print("herdr-relay: " + message, file=sys.stderr)
        sys.exit(1)
