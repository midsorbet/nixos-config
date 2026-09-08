import subprocess
import unittest
from unittest import mock

from hcloud_relay import (
    HcloudRelay,
    RelayError,
    relay_cleanup_errors,
    relay_command,
    safe_hcloud_diagnostic,
)


class RelayCommandErrorTests(unittest.TestCase):
    def test_hcloud_failure_reports_safe_bounded_diagnostic(self):
        overlapping_secret = "overlap-value"
        secret = f"prefix/1/{overlapping_secret}"
        safe_stderr = "server creation rejected; project quota remaining: 1/10"
        private_key = (
            "-----BEGIN OPENSSH PRIVATE KEY-----\n"
            "private-key-material\n"
            "-----END OPENSSH PRIVATE KEY-----"
        )
        stderr = (
            f"{safe_stderr}; credentials={secret},{overlapping_secret}\x00\n"
            f"{private_key}\n" + "additional native context " * 100
        )
        failure = subprocess.CalledProcessError(42, ["hcloud"], stderr=stderr)
        environment = {
            "PWD": "/",
            "SHLVL": "1",
            "BACKUP_SECRET": overlapping_secret,
            "HCLOUD_TOKEN": secret,
        }

        with mock.patch("hcloud_relay.subprocess.run", side_effect=failure):
            with self.assertRaises(RelayError) as raised:
                relay_command(
                    [
                        "hcloud",
                        "--config",
                        "/dev/null",
                        "--endpoint",
                        "https://api.hetzner.cloud/v1",
                        "--http-timeout",
                        "30s",
                        "server",
                        "create",
                    ],
                    environment=environment,
                )

        message = str(raised.exception)
        self.assertIn("hcloud", message)
        self.assertIn("server", message)
        self.assertIn("create", message)
        self.assertIn("exit code", message)
        self.assertIn("42", message)
        self.assertIn(safe_stderr, message)
        self.assertNotIn(secret, message)
        self.assertNotIn(overlapping_secret, message)
        self.assertNotIn(private_key, message)
        self.assertNotIn("private-key-material", message)

    def test_hcloud_diagnostic_normalizes_controls_and_bounds_long_output(self):
        long_stderr = "quota available\x00after refresh\n" + "native context " * 100

        diagnostic = safe_hcloud_diagnostic(long_stderr, {})
        longer_diagnostic = safe_hcloud_diagnostic(
            long_stderr + "native context " * 100, {}
        )

        self.assertIn("quota available after refresh", diagnostic)
        self.assertNotIn("\x00", diagnostic)
        self.assertNotIn("\n", diagnostic)
        self.assertTrue(diagnostic.endswith("..."))
        self.assertEqual(diagnostic, longer_diagnostic)

    def test_non_hcloud_failure_omits_unsafe_stderr(self):
        secret = "untrusted-command-secret"
        failure = subprocess.CalledProcessError(
            7,
            ["launchctl"],
            stderr=f"unsafe diagnostic containing {secret}",
        )

        with mock.patch("hcloud_relay.subprocess.run", side_effect=failure):
            with self.assertRaises(RelayError) as raised:
                relay_command(
                    ["launchctl", "kickstart"], environment={"API_SECRET": secret}
                )

        message = str(raised.exception)
        self.assertIn("launchctl", message)
        self.assertIn("kickstart", message)
        self.assertIn("exit code", message)
        self.assertIn("7", message)
        self.assertNotIn("unsafe diagnostic", message)
        self.assertNotIn(secret, message)

    def test_hcloud_failure_retains_official_api_error_code(self):
        failure = subprocess.CalledProcessError(
            1,
            ["hcloud"],
            stderr="server is locked (locked, 0123456789abcdef)\n",
        )

        with (
            mock.patch("hcloud_relay.subprocess.run", side_effect=failure),
            self.assertRaises(RelayError) as raised,
        ):
            relay_command(["hcloud", "server", "delete", "42"])

        self.assertEqual(raised.exception.hcloud_code, "locked")


class RelayDeletionTests(unittest.TestCase):
    def setUp(self):
        self.cloud = HcloudRelay.__new__(HcloudRelay)
        self.server = {
            "id": 42,
            "name": "hooh",
            "labels": {"herdr-relay": "hooh", "role": "session"},
        }

    def test_delete_failure_is_success_when_server_disappeared_concurrently(self):
        self.cloud.resources = mock.Mock(side_effect=[[self.server], []])
        self.cloud.run = mock.Mock(side_effect=RelayError("delete raced"))

        self.cloud.delete_server(42)

        self.assertEqual(self.cloud.run.call_args.args, ("server", "delete", 42))
        self.assertLessEqual(self.cloud.run.call_args.kwargs["timeout"], 30)

    def test_locked_delete_retries_with_fresh_ownership_until_absent(self):
        transient = RelayError("server is locked", hcloud_code="locked")
        self.cloud.resources = mock.Mock(
            side_effect=[[self.server], [self.server], [self.server], []]
        )
        self.cloud.run = mock.Mock(side_effect=[transient, None])

        with mock.patch("hcloud_relay.time.sleep"):
            self.cloud.delete_server(42)

        self.assertEqual(self.cloud.run.call_count, 2)
        self.assertEqual(self.cloud.resources.call_count, 4)

    def test_retry_refuses_server_whose_ownership_changed_while_waiting(self):
        transient = RelayError("resource changed", hcloud_code="conflict")
        foreign = {**self.server, "labels": {"herdr-relay": "someone-else"}}
        self.cloud.resources = mock.Mock(
            side_effect=[[self.server], [self.server], [foreign]]
        )
        self.cloud.run = mock.Mock(side_effect=transient)

        with (
            mock.patch("hcloud_relay.time.sleep"),
            self.assertRaisesRegex(RelayError, "ownership does not match"),
        ):
            self.cloud.delete_server(42)

        self.cloud.run.assert_called_once()

    def test_malformed_ownership_is_refused_without_delete_attempt(self):
        malformed = {**self.server, "labels": "herdr-relay=hooh"}
        self.cloud.resources = mock.Mock(return_value=[malformed])
        self.cloud.run = mock.Mock()

        with self.assertRaisesRegex(RelayError, "ownership does not match"):
            self.cloud.delete_server(42)

        self.cloud.run.assert_not_called()

    def test_permission_failure_is_not_retried_when_server_still_owned(self):
        forbidden = RelayError("insufficient permissions", hcloud_code="forbidden")
        self.cloud.resources = mock.Mock(side_effect=[[self.server], [self.server]])
        self.cloud.run = mock.Mock(side_effect=forbidden)

        with self.assertRaises(RelayError) as raised:
            self.cloud.delete_server(42)

        self.assertIs(raised.exception, forbidden)
        self.cloud.run.assert_called_once()

    def test_locked_retries_stop_at_one_absolute_deadline(self):
        transient = RelayError("server is locked", hcloud_code="locked")
        self.cloud.resources = mock.Mock(return_value=[self.server])
        self.cloud.run = mock.Mock(side_effect=transient)
        clock = iter([10.0, 10.0, 10.0, 10.0, 39.5, 39.5, 39.5, 39.5, 40.0])

        with (
            mock.patch("hcloud_relay.time.monotonic", side_effect=clock),
            mock.patch("hcloud_relay.time.sleep") as sleep,
            self.assertRaisesRegex(RelayError, "deadline"),
        ):
            self.cloud.delete_server(42)

        self.assertEqual(self.cloud.run.call_count, 2)
        sleep.assert_called_once_with(0.5)


class RelayCleanupErrorTests(unittest.TestCase):
    def test_cleanup_error_does_not_mask_active_failure(self):
        original = KeyboardInterrupt()

        with (
            mock.patch("hcloud_relay.sys.stderr") as stderr,
            self.assertRaises(KeyboardInterrupt) as raised,
        ):
            try:
                raise original
            finally:
                with relay_cleanup_errors():
                    raise RelayError("delete cleanup failed")

        self.assertIs(raised.exception, original)
        self.assertIn(
            "delete cleanup failed",
            "".join(call.args[0] for call in stderr.write.call_args_list),
        )

    def test_cleanup_error_propagates_without_active_failure(self):
        cleanup = RelayError("delete cleanup failed")

        with self.assertRaises(RelayError) as raised:
            with relay_cleanup_errors():
                raise cleanup

        self.assertIs(raised.exception, cleanup)


if __name__ == "__main__":
    unittest.main()
