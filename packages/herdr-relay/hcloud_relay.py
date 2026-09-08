"""Small adapters for the official hcloud CLI, not a second Hetzner API client."""

import json
import os
import re
import subprocess
import time
from pathlib import Path

OWNER_SELECTOR = "herdr-relay=hooh"
SERVER_ROLES = {"hooh": "session", "hooh-image-builder": "image-builder"}


class RelayError(RuntimeError):
    """A user-facing error that never contains credential values."""


COMMAND_DIAGNOSTIC_LIMIT = 512
HCLOUD_GLOBAL_OPTIONS_WITH_VALUES = {"--config", "--endpoint", "--http-timeout"}
CREDENTIAL_ENV_SUFFIXES = ("_TOKEN", "_SECRET", "_PASSWORD", "_KEY")
PRIVATE_KEY_PATTERN = re.compile(
    r"-----BEGIN [^-\r\n]*PRIVATE KEY-----.*?-----END [^-\r\n]*PRIVATE KEY-----",
    re.DOTALL,
)


def relay_command_description(arguments):
    """Describe a tool and subcommand without copying possibly secret arguments."""
    executable = Path(arguments[0]).name
    if executable != "hcloud":
        return " ".join(map(str, arguments[:2]))

    subcommands = []
    index = 1
    while index < len(arguments) and len(subcommands) < 2:
        argument = str(arguments[index])
        if argument in HCLOUD_GLOBAL_OPTIONS_WITH_VALUES:
            index += 2
        elif argument.startswith("-"):
            index += 1
        else:
            subcommands.append(argument)
            index += 1
    return " ".join(["hcloud", *subcommands])


def safe_hcloud_diagnostic(stderr, environment):
    """Return bounded hcloud stderr with credentials and private keys removed."""
    diagnostic = PRIVATE_KEY_PATTERN.sub("<redacted private key>", stderr or "")
    credential_values = {
        str(value)
        for name, value in (environment or {}).items()
        if value and str(name).upper().endswith(CREDENTIAL_ENV_SUFFIXES)
    }
    for value in sorted(credential_values, key=len, reverse=True):
        diagnostic = diagnostic.replace(value, "<redacted>")
    diagnostic = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", diagnostic)
    diagnostic = " ".join(diagnostic.split())
    if len(diagnostic) > COMMAND_DIAGNOSTIC_LIMIT:
        diagnostic = diagnostic[:COMMAND_DIAGNOSTIC_LIMIT].rstrip() + "..."
    return diagnostic


def relay_command(arguments, *, timeout=120, capture=True, environment=None):
    """Run an existing tool with bounded execution and no shell interpolation."""
    try:
        return subprocess.run(
            arguments,
            check=True,
            timeout=timeout,
            text=True,
            capture_output=capture,
            env=environment,
        ).stdout
    except subprocess.CalledProcessError as error:
        description = relay_command_description(arguments)
        message = f"{description} failed with exit code {error.returncode}"
        if Path(arguments[0]).name == "hcloud":
            diagnostic = safe_hcloud_diagnostic(error.stderr, environment)
            if diagnostic:
                message += f": {diagnostic}"
        raise RelayError(message) from None
    except subprocess.TimeoutExpired:
        raise RelayError(
            f"{Path(arguments[0]).name} timed out; check status for unfinished cloud operations"
        ) from None


class HcloudRelay:
    """Let hcloud handle API authentication, pagination and asynchronous cloud actions."""

    def __init__(self, token_file):
        token = Path(token_file).read_text().strip()
        if not token or any(character.isspace() for character in token):
            raise RelayError("The Hetzner token file is empty or malformed")
        self.environment = {**os.environ, "HCLOUD_TOKEN": token}

    def run(self, *arguments, timeout=900):
        return relay_command(
            [
                "hcloud",
                "--config",
                "/dev/null",
                "--endpoint",
                "https://api.hetzner.cloud/v1",
                "--http-timeout",
                "30s",
                *map(str, arguments),
            ],
            timeout=timeout,
            environment=self.environment,
        )

    def resources(self, kind, selector=OWNER_SELECTOR, *filters):
        arguments = [kind, "list", "--output", "json", *filters]
        if selector:
            arguments.extend(["--selector", selector])
        return json.loads(self.run(*arguments))

    def owned_servers(self):
        return [
            server for server in self.resources("server") if is_relay_server(server)
        ]

    def delete_server(self, server_id):
        """Delete only a freshly verified owned ID, then confirm its absence."""
        matches = [
            server
            for server in self.resources("server", None)
            if server["id"] == server_id
        ]
        if not matches:
            return
        if len(matches) != 1 or not is_relay_server(matches[0]):
            raise RelayError(
                f"Refusing to delete server {server_id}: ownership does not match"
            )
        self.run("server", "delete", server_id)
        for _ in range(5):
            if all(
                server["id"] != server_id for server in self.resources("server", None)
            ):
                return
            time.sleep(1)
        raise RelayError(f"Server {server_id} still exists after deletion")


def is_relay_server(server):
    """Only the two fixed Hooh server names and matching labels are deletable."""
    labels = server.get("labels", {})
    expected_role = SERVER_ROLES.get(server.get("name"))
    return (
        expected_role is not None
        and labels.get("herdr-relay") == "hooh"
        and labels.get("role") == expected_role
    )


def relay_expiry(server):
    """Require an absolute epoch expiry; malformed leases are never deleted by guessing."""
    value = server.get("labels", {}).get("expires-at", "")
    if (
        not isinstance(value, str)
        or not value.isascii()
        or not value.isdecimal()
        or len(value) > 12
    ):
        raise RelayError(f"Server {server.get('id')} has an invalid expiry label")
    return int(value)


def one_relay_resource(resources, description):
    """Refuse ambiguous retained resources rather than choosing a billable object arbitrarily."""
    if len(resources) != 1:
        raise RelayError(
            f"Expected exactly one {description}; run prepare or inspect project resources"
        )
    return resources[0]


def relay_network(cloud):
    """Read existing resources; starting a session never provisions persistent infrastructure."""
    endpoint = one_relay_resource(
        cloud.resources("primary-ip", OWNER_SELECTOR + ",role=endpoint"),
        "retained IPv4",
    )
    firewall = one_relay_resource(
        cloud.resources("firewall", OWNER_SELECTOR + ",role=firewall"), "relay firewall"
    )
    if endpoint.get("type") != "ipv4" or endpoint.get("auto_delete") is not False:
        raise RelayError("Hooh must use a retained Primary IPv4")
    location = endpoint.get("location") or endpoint.get("datacenter", {}).get(
        "location", {}
    )
    if location.get("name") != "hil":
        raise RelayError("Hooh's retained IPv4 is not in Hillsboro")
    return endpoint, firewall


def refuse_existing_hooh(cloud):
    """Fixed names and a local operation lock prevent duplicate session or builder creation."""
    if any(
        server.get("name") in SERVER_ROLES for server in cloud.resources("server", None)
    ):
        raise RelayError(
            "Hooh or its image builder already exists; inspect status before creating another"
        )


def write_relay_userdata(path, expiry, role, extra=None):
    """Hetzner metadata carries only a finite lease, plus bootstrap keys during preparation."""
    data = {"herdr_relay": {"expires_at": expiry, "role": role}, **(extra or {})}
    Path(path).write_text("#cloud-config\n" + json.dumps(data) + "\n")
    Path(path).chmod(0o600)
