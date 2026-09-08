import subprocess
import unittest
from unittest import mock

from hcloud_relay import RelayError, relay_command, safe_hcloud_diagnostic


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


if __name__ == "__main__":
    unittest.main()
