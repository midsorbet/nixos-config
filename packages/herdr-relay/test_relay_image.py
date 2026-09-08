import json
import os
import stat
import subprocess
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parent))

import relay_image
from hcloud_relay import OWNER_SELECTOR, RelayError


class FakeClock:
    def __init__(self):
        self.now = 0.0

    def monotonic(self):
        return self.now

    def sleep(self, seconds):
        self.now += seconds


class FakeCloud:
    def __init__(self):
        self.created = False
        self.deleted = []
        self.expiry = None
        self.userdata_expiry = None

    def resources(self, kind, selector=OWNER_SELECTOR, *filters):
        if kind == "server":
            return []
        if kind == "primary-ip":
            return [
                {
                    "id": "ip-1",
                    "ip": "192.0.2.10",
                    "type": "ipv4",
                    "auto_delete": False,
                    "assignee_id": None,
                    "location": {"name": "hil"},
                }
            ]
        if kind == "firewall":
            return [{"id": "firewall-1", "name": "hooh-frp"}]
        if kind == "ssh-key":
            return [
                {
                    "id": "key-1",
                    "name": "hooh-admin",
                    "public_key": "ssh-ed25519 PUBLIC",
                }
            ]
        if kind == "image" and "--architecture" in filters:
            return [{"id": "debian-13", "name": "debian-13", "status": "available"}]
        if kind == "image":
            return [{"id": "snapshot-1", "status": "available"}]
        raise AssertionError((kind, selector, filters))

    def run(self, *arguments, timeout=900):
        if arguments[:2] == ("server", "create"):
            self.created = True
            expiry_label = next(
                value for value in arguments if str(value).startswith("expires-at=")
            )
            self.expiry = int(expiry_label.split("=", 1)[1])
            userdata = Path(
                arguments[arguments.index("--user-data-from-file") + 1]
            ).read_text()
            cloud_config = json.loads(userdata.split("\n", 1)[1])
            lease = json.loads(cloud_config["write_files"][0]["content"])
            self.userdata_expiry = lease["herdr_relay"]["expires_at"]
            return ""
        if arguments[:2] == ("server", "describe"):
            return json.dumps({"status": "off"})
        return ""

    def owned_servers(self):
        if not self.created or self.deleted:
            return []
        return [
            {
                "id": "builder-1",
                "name": "hooh-image-builder",
                "labels": {
                    "herdr-relay": "hooh",
                    "role": "image-builder",
                    "expires-at": str(self.expiry),
                },
            }
        ]

    def delete_server(self, server_id):
        self.deleted.append(server_id)


def command_result(arguments, *, timeout=120, capture=True, environment=None):
    if arguments[:3] == ["nix", "eval", "--raw"]:
        return "/nix/store/hooh-system\n"
    if arguments[0] == "ssh-keygen":
        return "ssh-ed25519 PUBLIC\n"
    if arguments[0] == "nixos-anywhere":
        return ""
    raise AssertionError(arguments)


class RelayImagePermissionsTest(unittest.TestCase):
    def test_staged_and_extracted_host_key_permissions_survive_umask(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary = Path(temporary)
            root = temporary / "root"
            previous_umask = os.umask(0o077)
            try:
                private_file = relay_image.stage_relay_host_key(root, "PRIVATE\n")
                expected_modes = {
                    root: 0o755,
                    root / "etc": 0o755,
                    root / "etc" / "ssh": 0o755,
                    private_file: 0o600,
                }
                for path, mode in expected_modes.items():
                    self.assertEqual(stat.S_IMODE(path.stat().st_mode), mode)

                archive = temporary / "extra-files.tar"
                with tarfile.open(archive, "w") as output:
                    output.add(root, arcname="root")
                extracted = temporary / "extracted"
                extracted.mkdir()
                with tarfile.open(archive) as input_archive:
                    input_archive.extractall(extracted, filter="fully_trusted")
                for path, mode in expected_modes.items():
                    relative = path.relative_to(temporary)
                    self.assertEqual(
                        stat.S_IMODE((extracted / relative).stat().st_mode), mode
                    )
                self.assertEqual(stat.S_IMODE(temporary.stat().st_mode), 0o700)
            finally:
                os.umask(previous_umask)


class RelaySshWaitTest(unittest.TestCase):
    config = {"sshCommand": "ssh", "adminKeyFile": "/private/admin"}

    def test_known_hosts_path_with_spaces_remains_one_ssh_file(self):
        run = subprocess.run
        known_hosts = "/tmp/Application Support/relay/known_hosts"

        def inspect_ssh_config(arguments, **kwargs):
            return run([arguments[0], "-G", *arguments[1:]], **kwargs)

        with patch.object(
            relay_image.subprocess, "run", side_effect=inspect_ssh_config
        ):
            output = relay_image.wait_relay_ssh(
                self.config, known_hosts, "192.0.2.1", "root", "true"
            )
        line = next(
            line
            for line in output.splitlines()
            if line.startswith("userknownhostsfile ")
        )
        self.assertEqual(line, f"userknownhostsfile {known_hosts}")

    def test_subprocess_timeout_is_retried_until_ready(self):
        clock = FakeClock()
        timeout = subprocess.TimeoutExpired(["ssh"], 15)
        ready = subprocess.CompletedProcess(["ssh"], 0, stdout="ready\n", stderr="")
        with (
            patch.object(relay_image.time, "monotonic", side_effect=clock.monotonic),
            patch.object(relay_image.time, "sleep", side_effect=clock.sleep),
            patch.object(relay_image.subprocess, "run", side_effect=[timeout, ready]),
        ):
            result = relay_image.wait_relay_ssh(
                self.config,
                Path("/private/known_hosts"),
                "192.0.2.10",
                "root",
                "true",
                timeout=30,
            )

        self.assertEqual(result, "ready")

    def test_permanent_subprocess_timeout_ends_at_overall_deadline(self):
        clock = FakeClock()

        def expire_attempt(arguments, **options):
            clock.now += options["timeout"]
            raise subprocess.TimeoutExpired(arguments, options["timeout"])

        with (
            patch.object(relay_image.time, "monotonic", side_effect=clock.monotonic),
            patch.object(relay_image.time, "sleep", side_effect=clock.sleep),
            patch.object(relay_image.subprocess, "run", side_effect=expire_attempt),
        ):
            with self.assertRaises(RelayError):
                relay_image.wait_relay_ssh(
                    self.config,
                    Path("/private/known_hosts"),
                    "192.0.2.10",
                    "root",
                    "true",
                    timeout=31,
                )

        self.assertEqual(clock.now, 31)


class RelayImageLeaseTest(unittest.TestCase):
    def prepare_fixture(self, temporary):
        temporary = Path(temporary)
        state = temporary / "state"
        state.mkdir()
        flake = temporary / "flake"
        flake.mkdir()
        (flake / "flake.nix").write_text("{}\n")
        host_key = temporary / "host-key"
        host_key.write_text("PRIVATE\n")
        config = {
            "adminKeyFile": str(temporary / "admin-key"),
            "hostKeyFile": str(host_key),
            "hostPublicKey": "ssh-ed25519 PUBLIC",
            "hostname": "mini.example.test",
            "imageIdentity": "test-identity",
            "sshCommand": "ssh",
        }
        return state, flake, config

    def test_expiry_is_established_after_preparation_with_complete_phase_budget(self):
        cloud = FakeCloud()
        clock = FakeClock()
        clock.now = 1_000_000

        def elapse_during_preparation(arguments, **options):
            if not cloud.created:
                clock.sleep(300)
            return command_result(arguments, **options)

        with tempfile.TemporaryDirectory() as temporary:
            state, flake, config = self.prepare_fixture(temporary)
            with (
                patch.object(
                    relay_image, "relay_command", side_effect=elapse_during_preparation
                ),
                patch.object(
                    relay_image,
                    "wait_relay_ssh",
                    side_effect=["", "/nix/store/hooh-system"],
                ),
                patch.object(relay_image.time, "time", side_effect=lambda: clock.now),
            ):
                result = relay_image.prepare_relay_image(config, state, cloud, flake)

        self.assertGreater(clock.now, 1_000_000)
        self.assertEqual(cloud.expiry - clock.now, relay_image.BUILDER_LEASE_SECONDS)
        self.assertEqual(cloud.userdata_expiry, cloud.expiry)
        self.assertEqual(result["snapshotId"], "snapshot-1")
        self.assertEqual(cloud.deleted, ["builder-1"])

    def test_failed_preparation_deletes_created_builder(self):
        cloud = FakeCloud()
        with tempfile.TemporaryDirectory() as temporary:
            state, flake, config = self.prepare_fixture(temporary)
            with (
                patch.object(relay_image, "relay_command", side_effect=command_result),
                patch.object(
                    relay_image,
                    "wait_relay_ssh",
                    side_effect=RelayError("bootstrap failed"),
                ),
                patch.object(relay_image.time, "time", return_value=1_000_000),
            ):
                with self.assertRaises(RelayError):
                    relay_image.prepare_relay_image(config, state, cloud, flake)

        self.assertTrue(cloud.created)
        self.assertEqual(cloud.deleted, ["builder-1"])

    def test_shutdown_polling_deadline_refuses_snapshot_and_deletes_builder(self):
        clock = FakeClock()

        class SlowShutdownCloud(FakeCloud):
            def __init__(self):
                super().__init__()
                self.snapshot_attempted = False

            def run(self, *arguments, timeout=900):
                if arguments[:2] == ("server", "describe"):
                    clock.sleep(timeout)
                    return json.dumps({"status": "running"})
                if arguments[:2] == ("server", "create-image"):
                    self.snapshot_attempted = True
                return super().run(*arguments, timeout=timeout)

        cloud = SlowShutdownCloud()
        with tempfile.TemporaryDirectory() as temporary:
            state, flake, config = self.prepare_fixture(temporary)
            with (
                patch.object(relay_image, "relay_command", side_effect=command_result),
                patch.object(
                    relay_image,
                    "wait_relay_ssh",
                    side_effect=["", "/nix/store/hooh-system"],
                ),
                patch.object(relay_image.time, "time", return_value=1_000_000),
                patch.object(
                    relay_image.time, "monotonic", side_effect=clock.monotonic
                ),
                patch.object(relay_image.time, "sleep", side_effect=clock.sleep),
            ):
                with self.assertRaises(RelayError):
                    relay_image.prepare_relay_image(config, state, cloud, flake)

        self.assertFalse(cloud.snapshot_attempted)
        self.assertEqual(cloud.deleted, ["builder-1"])


if __name__ == "__main__":
    unittest.main()
