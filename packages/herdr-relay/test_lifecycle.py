import argparse
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import herdr_relay
from herdr_relay import RelayError


class RelayLifecycleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.state = Path(self.temporary.name)
        self.config = {
            "hostname": "herdr.example.test",
            "tunnelId": "tunnel-id",
            "tunnelConfig": "/nix/store/cloudflared.yml",
            "metricsAddress": "127.0.0.1:17478",
        }

    def test_ttl_bounds(self):
        self.assertEqual(herdr_relay.parse_relay_ttl("12h"), 43200)
        self.assertEqual(herdr_relay.parse_relay_ttl("30m"), 1800)
        for value in ("0", "13h", "12h1s"):
            with self.subTest(value=value), self.assertRaises(argparse.ArgumentTypeError):
                herdr_relay.parse_relay_ttl(value)

    def test_operation_lock_rejects_concurrent_mutation(self):
        with herdr_relay.relay_lock(self.state):
            with self.assertRaises(RelayError):
                with herdr_relay.relay_lock(self.state):
                    pass

    def test_start_cannot_extend_active_lease(self):
        herdr_relay.write_relay_lease(self.state, 2000)
        with mock.patch.object(herdr_relay.time, "time", return_value=1000):
            with self.assertRaises(RelayError):
                herdr_relay.start_relay(self.config, self.state, 3600)
        self.assertEqual(herdr_relay.read_relay_expiry(self.state), 2000)

    def test_occupied_metrics_endpoint_cannot_authorize_a_lease(self):
        with mock.patch.object(herdr_relay, "metrics_endpoint_occupied", return_value=True):
            with self.assertRaises(RelayError):
                herdr_relay.start_relay(self.config, self.state, 60)
        self.assertIsNone(herdr_relay.read_relay_expiry(self.state))

    def test_start_failure_revokes_lease_before_cleanup(self):
        def observe_cleanup():
            self.assertIsNone(herdr_relay.read_relay_expiry(self.state))

        with (
            mock.patch.object(herdr_relay, "metrics_endpoint_occupied", return_value=False),
            mock.patch.object(herdr_relay.subprocess, "run", side_effect=OSError("no launchd")),
            mock.patch.object(herdr_relay, "signal_relay_connector", side_effect=observe_cleanup),
        ):
            with self.assertRaises(OSError):
                herdr_relay.start_relay(self.config, self.state, 60)
        self.assertIsNone(herdr_relay.read_relay_expiry(self.state))

    def test_stop_failure_is_reported_but_lease_stays_revoked(self):
        herdr_relay.write_relay_lease(self.state, 2000)
        with mock.patch.object(
            herdr_relay.subprocess, "run", return_value=subprocess.CompletedProcess([], 1)
        ):
            with self.assertRaises(RelayError):
                herdr_relay.stop_relay(self.config, self.state)
        self.assertIsNone(herdr_relay.read_relay_expiry(self.state))

    def test_stop_without_running_process_is_idempotent(self):
        with (
            mock.patch.object(
                herdr_relay.subprocess, "run", return_value=subprocess.CompletedProcess([], 3)
            ),
            mock.patch.object(herdr_relay, "metrics_endpoint_occupied", return_value=False),
        ):
            herdr_relay.stop_relay(self.config, self.state)
        self.assertEqual(herdr_relay.relay_status(self.config, self.state)["status"], "stopped")

    def test_status_distinguishes_expiry_from_reconnecting(self):
        herdr_relay.write_relay_lease(self.state, 999)
        with mock.patch.object(herdr_relay.time, "time", return_value=1000):
            self.assertEqual(herdr_relay.relay_status(self.config, self.state)["status"], "expired")
        herdr_relay.write_relay_lease(self.state, 2000)
        with (
            mock.patch.object(herdr_relay.time, "time", return_value=1000),
            mock.patch.object(herdr_relay, "cloudflared_ready", return_value=False),
        ):
            self.assertEqual(herdr_relay.relay_status(self.config, self.state)["status"], "connecting")


if __name__ == "__main__":
    unittest.main()
