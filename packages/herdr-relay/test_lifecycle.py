import base64
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import herdr_relay
from hcloud_relay import RelayError


def ed25519_public_key(key=bytes(range(32))):
    algorithm = b"ssh-ed25519"
    blob = (
        struct.pack(">I", len(algorithm))
        + algorithm
        + struct.pack(">I", len(key))
        + key
    )
    return "ssh-ed25519 " + base64.b64encode(blob).decode("ascii")


class SessionCloud:
    def __init__(self, owned_server_results=()):
        self.created = False
        self.deleted = []
        self.owned_server_results = iter(owned_server_results)

    def resources(self, kind, selector=None, *filters):
        if kind == "image":
            return [{"id": 7, "status": "available", "created": "2026-09-07T00:00:00Z"}]
        raise AssertionError(f"Unexpected resource lookup: {kind}")

    def run(self, *arguments, **kwargs):
        if arguments[:2] != ("server", "create"):
            raise AssertionError(f"Unexpected cloud command: {arguments}")
        self.created = True

    def owned_servers(self):
        return next(self.owned_server_results, [])

    def delete_server(self, server_id):
        self.deleted.append(server_id)


class RelayLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.state = Path(self.temporary.name)
        self.host_key = self.state / "ssh_host_ed25519_key.pub"
        self.config = {
            "hostname": "relay.example.test",
            "imageIdentity": "signed-image-identity",
            "miniHostPublicKeyFile": str(self.host_key),
        }

    def start_relay(self, cloud, *, verify=None):
        verify_patch = mock.patch.object(
            herdr_relay, "verify_mini_endpoint", side_effect=verify
        )
        launchctl_result = subprocess.CompletedProcess([], 0)
        with (
            mock.patch.object(herdr_relay.sys, "platform", "darwin"),
            mock.patch.object(herdr_relay, "refuse_existing_hooh"),
            mock.patch.object(
                herdr_relay,
                "relay_network",
                return_value=(
                    {"id": 8, "ip": "192.0.2.20", "assignee_id": None},
                    {"id": 9},
                ),
            ),
            mock.patch.object(
                herdr_relay.socket,
                "getaddrinfo",
                return_value=[(None, None, None, None, ("192.0.2.20", 2222))],
            ),
            mock.patch.object(herdr_relay, "relay_command"),
            mock.patch.object(
                herdr_relay.subprocess, "run", return_value=launchctl_result
            ),
            mock.patch.object(herdr_relay.time, "time", return_value=1000),
            verify_patch,
        ):
            return herdr_relay.start_relay(self.config, self.state, cloud, 60)

    def test_comment_only_host_key_prevents_server_creation(self):
        self.host_key.write_text("# no trusted host key\n\n")
        cloud = SessionCloud()

        with self.assertRaises(RelayError):
            self.start_relay(cloud)

        self.assertFalse(cloud.created)

    def test_keyscan_timeouts_and_wrong_keys_wait_for_expected_identity(self):
        expected = ed25519_public_key().split()
        self.host_key.write_text(ed25519_public_key() + " mini\n")
        other = ed25519_public_key(bytes([1]) * 32).split()
        completed = lambda output: subprocess.CompletedProcess(
            [], 0, stdout=output, stderr=""
        )
        probes = iter(
            [
                subprocess.TimeoutExpired("ssh-keyscan", 10),
                completed(f"# banner\n[192.0.2.20]:2222 {other[0]} {other[1]}\n"),
                completed(f"[192.0.2.20]:2222 {expected[0]} {expected[1]}\n"),
            ]
        )
        expected_identity_became_available = False

        def probe_until_expected_identity(*arguments, **kwargs):
            nonlocal expected_identity_became_available
            result = next(probes)
            if isinstance(result, Exception):
                raise result
            if expected[1] in result.stdout:
                expected_identity_became_available = True
            return result

        with (
            mock.patch.object(
                herdr_relay.subprocess, "run", side_effect=probe_until_expected_identity
            ),
            mock.patch.object(herdr_relay.time, "time", return_value=100),
            mock.patch.object(herdr_relay.time, "sleep"),
        ):
            herdr_relay.verify_mini_endpoint(self.config, "192.0.2.20", 200)

        self.assertTrue(expected_identity_became_available)

    def test_keyscan_timeouts_end_at_readiness_deadline(self):
        self.host_key.write_text(ed25519_public_key() + " mini\n")
        clock = [100.0]

        def timeout_probe(*arguments, **kwargs):
            clock[0] += kwargs["timeout"]
            raise subprocess.TimeoutExpired("ssh-keyscan", kwargs["timeout"])

        with (
            mock.patch.object(herdr_relay.subprocess, "run", side_effect=timeout_probe),
            mock.patch.object(herdr_relay.time, "time", side_effect=lambda: clock[0]),
        ):
            with self.assertRaises(RelayError):
                herdr_relay.verify_mini_endpoint(self.config, "192.0.2.20", 102)

        self.assertEqual(clock[0], 102)

    def test_missing_postcreate_server_is_relay_error_and_created_server_is_cleaned(
        self,
    ):
        self.host_key.write_text(ed25519_public_key() + " mini\n")
        server = {"id": 41, "name": "hooh", "labels": {"expires-at": "1060"}}
        cloud = SessionCloud([[], [server]])

        with self.assertRaises(RelayError):
            self.start_relay(cloud)

        self.assertTrue(cloud.created)
        self.assertEqual(cloud.deleted, [41])
        self.assertFalse((self.state / "lease.json").exists())

    def test_readiness_cancellation_invalidates_lease_and_cleans_server(self):
        self.host_key.write_text(ed25519_public_key() + " mini\n")
        server = {"id": 42, "name": "hooh", "labels": {"expires-at": "1060"}}
        cloud = SessionCloud([[server], [server]])

        with self.assertRaises(KeyboardInterrupt):
            self.start_relay(cloud, verify=KeyboardInterrupt())

        self.assertEqual(cloud.deleted, [42])
        self.assertFalse((self.state / "lease.json").exists())


if __name__ == "__main__":
    unittest.main()
