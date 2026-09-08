"""Prepare Hooh with hcloud and nixos-anywhere; never implement their APIs here."""

import json
import os
import subprocess
import tempfile
import time
from pathlib import Path

from hcloud_relay import (
    OWNER_SELECTOR, RelayError, one_relay_resource, refuse_existing_hooh,
    relay_command, relay_expiry, relay_network, write_relay_userdata,
)


def prepare_relay_network(cloud, temporary, admin_public):
    """Create retained resources only during explicit image preparation."""
    for kind, name, role in [("primary-ip", "hooh-ipv4", "endpoint"), ("firewall", "hooh-frp", "firewall"), ("ssh-key", "hooh-admin", "admin")]:
        existing = cloud.resources(kind, OWNER_SELECTOR + ",role=" + role)
        if existing:
            one_relay_resource(existing, role)
            continue
        if any(resource["name"] == name for resource in cloud.resources(kind, None)):
            raise RelayError(f"Refusing to reuse foreign {kind} named {name}")
        arguments = [kind, "create", "--name", name, "--label", OWNER_SELECTOR, "--label", "role=" + role]
        if kind == "primary-ip":
            arguments += ["--type", "ipv4", "--location", "hil", "--auto-delete=false"]
        elif kind == "firewall":
            rules = temporary / "firewall.json"
            rules.write_text(json.dumps([
                {"direction": "in", "protocol": "tcp", "port": str(port), "source_ips": ["0.0.0.0/0"]}
                for port in (22, 2222, 7000)
            ] + [{"direction": "in", "protocol": "icmp", "source_ips": ["0.0.0.0/0"]}]))
            arguments += ["--rules-file", rules]
        else:
            public_file = temporary / "admin.pub"
            public_file.write_text(admin_public + "\n")
            arguments += ["--public-key-from-file", public_file]
        cloud.run(*arguments)
    return relay_network(cloud)


def wait_relay_ssh(config, known_hosts, address, user, command, timeout=240):
    """Wait through boot, but never bypass the pre-provisioned SSH host identity."""
    deadline = time.time() + timeout
    arguments = [
        config["sshCommand"], "-F", "/dev/null", "-i", config["adminKeyFile"],
        "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5",
        "-o", "StrictHostKeyChecking=yes", "-o", f"UserKnownHostsFile={known_hosts}",
        f"{user}@{address}", command,
    ]
    while time.time() < deadline:
        result = subprocess.run(arguments, text=True, capture_output=True, timeout=15)
        if result.returncode == 0:
            return result.stdout.strip()
        if "REMOTE HOST IDENTIFICATION HAS CHANGED" in result.stderr:
            raise RelayError("Hooh SSH host identity does not match the canonical key")
        time.sleep(3)
    raise RelayError("Hooh did not become ready with its expected SSH identity")


def prepare_relay_image(config, state, cloud, flake):
    """Build one reusable frp snapshot; the temporary builder is deleted on every exit path."""
    flake = str(Path(flake).resolve())
    if not (Path(flake) / "flake.nix").is_file():
        raise RelayError("prepare --flake requires the local nixos-config worktree")
    expected_system = relay_command(["nix", "eval", "--raw", flake + "#nixosConfigurations.hooh.config.system.build.toplevel"], timeout=180).strip()
    admin_public = relay_command(["ssh-keygen", "-y", "-f", config["adminKeyFile"]]).strip()
    host_public = relay_command(["ssh-keygen", "-y", "-f", config["hostKeyFile"]]).split()[:2]
    if host_public != config["hostPublicKey"].split()[:2]:
        raise RelayError("Hooh's decrypted private host key does not match the configured public key")
    refuse_existing_hooh(cloud)
    expiry = int(time.time()) + 7200
    with tempfile.TemporaryDirectory(prefix="image-", dir=state) as temporary:
        temporary = Path(temporary)
        endpoint, firewall = prepare_relay_network(cloud, temporary, admin_public)
        if endpoint.get("assignee_id") is not None:
            raise RelayError("The retained IPv4 is already assigned")
        images = cloud.resources("image", None, "--type", "system", "--architecture", "x86")
        base_image = next((image for image in images if image.get("name") == "debian-13" and image["status"] == "available"), None)
        if base_image is None:
            raise RelayError("Debian 13 is unavailable as a bootstrap image")
        admin_key = one_relay_resource(cloud.resources("ssh-key", OWNER_SELECTOR + ",role=admin"), "admin public key")
        if admin_key.get("public_key", "").split()[:2] != admin_public.split()[:2]:
            raise RelayError("Retained admin public key does not match Mini's configured identity")
        root = temporary / "root"
        ssh_directory = root / "etc" / "ssh"
        ssh_directory.mkdir(parents=True, mode=0o700)
        host_private = Path(config["hostKeyFile"]).read_text()
        private_file = ssh_directory / "ssh_host_ed25519_key"
        private_file.write_text(host_private)
        private_file.chmod(0o600)
        userdata = temporary / "user-data"
        write_relay_userdata(userdata, expiry, "image-builder", {
            "ssh_keys": {"ed25519_private": host_private, "ed25519_public": config["hostPublicKey"]},
            "ssh_pwauth": False,
        })
        known_hosts = temporary / "known_hosts"
        known_hosts.write_text(f"{endpoint['ip']} {config['hostPublicKey'].strip()}\n")
        try:
            cloud.run(
                "server", "create", "--name", "hooh-image-builder", "--type", "cpx11", "--location", "hil",
                "--image", base_image["id"], "--ssh-key", admin_key["id"],
                "--primary-ipv4", endpoint["id"], "--without-ipv6", "--firewall", firewall["id"],
                "--label", OWNER_SELECTOR, "--label", "role=image-builder", "--label", f"expires-at={expiry}",
                "--user-data-from-file", userdata,
            )
            builder = one_relay_resource([server for server in cloud.owned_servers() if server["name"] == "hooh-image-builder"], "image builder")
            wait_relay_ssh(config, known_hosts, endpoint["ip"], "root", "cloud-init status --wait >/dev/null")
            # The package patches nixos-anywhere's insecure defaults so these options actually win.
            relay_command([
                "nixos-anywhere", "--flake", flake + "#hooh", "--target-host", f"root@{endpoint['ip']}",
                "-i", config["adminKeyFile"], "--extra-files", str(root), "--build-on", "remote",
                "--ssh-option", "StrictHostKeyChecking=yes", "--ssh-option", f"UserKnownHostsFile={known_hosts}",
            ], timeout=5400, capture=False)
            verification = (
                "test \"$(hostname)\" = hooh && systemctl is-active --quiet frp-hooh && "
                f"sudo -n jq -e '.herdr_relay.expires_at == {expiry}' /run/herdr-relay/lease.json >/dev/null && "
                "readlink -f /run/current-system"
            )
            installed = wait_relay_ssh(config, known_hosts, endpoint["ip"], "me", verification)
            if installed != expected_system:
                raise RelayError("Installed Hooh system does not match the selected flake build")
            cloud.run("server", "shutdown", builder["id"])
            for _ in range(60):
                server = json.loads(cloud.run("server", "describe", builder["id"], "--output", "json"))
                if server["status"] == "off":
                    break
                time.sleep(2)
            else:
                raise RelayError("Builder did not shut down; refusing an inconsistent snapshot")
            cloud.run(
                "server", "create-image", builder["id"], "--type", "snapshot", "--description", "Hooh frp relay",
                "--label", OWNER_SELECTOR, "--label", "role=relay-image", "--label", f"identity={config['imageIdentity']}",
                "--label", f"build={expiry}", timeout=1800,
            )
            snapshot = one_relay_resource(cloud.resources("image", OWNER_SELECTOR + f",role=relay-image,build={expiry}", "--type", "snapshot"), "new relay snapshot")
            if snapshot["status"] != "available":
                raise RelayError("The new relay snapshot is not available")
            return {"snapshotId": snapshot["id"], "ipv4": endpoint["ip"], "nextStep": f"Set a DNS-only A record for {config['hostname']} to this IPv4"}
        finally:
            # hcloud handles action polling. Labels let Baymax recover if this machine disappears.
            for server in cloud.owned_servers():
                if server["name"] == "hooh-image-builder" and relay_expiry(server) == expiry:
                    cloud.delete_server(server["id"])
