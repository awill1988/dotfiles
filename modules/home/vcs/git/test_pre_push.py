"""Exercise a built pre-push hook with isolated repositories and signing keys."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


class PrePushTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.environment = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.root),
            "GIT_CONFIG_NOSYSTEM": "1",
            "GIT_CONFIG_GLOBAL": os.devnull,
        }
        self.hook = Path(os.environ["PRE_PUSH_HOOK"]).resolve(strict=True)
        self.run_command("git", "init", "--quiet", "--initial-branch=topic")
        for key, value in {
            "user.name": "hook test",
            "user.email": "hook@example.invalid",
            "gpg.format": "ssh",
            "user.signingkey": str(self.root / "key"),
            "gpg.ssh.allowedSignersFile": str(self.root / "allowed_signers"),
        }.items():
            self.run_command("git", "config", key, value)
        self.run_command("ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(self.root / "key"))
        public_key = (self.root / "key.pub").read_text()
        (self.root / "allowed_signers").write_text(f"hook@example.invalid {public_key}")
        self.base = self.commit("base", signed=False)
        self.run_command("git", "update-ref", "refs/remotes/origin/topic", self.base)

    def run_command(self, *command):
        return subprocess.run(command, cwd=self.root, env=self.environment,
                              check=True, text=True, capture_output=True).stdout.strip()

    def commit(self, subject, signed=True):
        self.run_command("git", "commit", "--quiet", "--allow-empty",
                         "-S" if signed else "--no-gpg-sign", "-m", subject)
        return self.run_command("git", "rev-parse", "HEAD")

    def push(self, head, remote=None):
        return subprocess.run(
            [str(self.hook), "origin", "unused"], cwd=self.root,
            env=self.environment, text=True, capture_output=True,
            input=f"refs/heads/topic {head} refs/heads/topic {remote or self.base}\n",
        )

    def published_unsigned_commit(self):
        revision = self.commit("published merge", signed=False)
        self.run_command("git", "update-ref", "refs/remotes/origin/main", revision)
        return revision

    def test_existing_branch_accepts_signed_tip_on_remote_unsigned_history(self):
        self.published_unsigned_commit()
        result = self.push(self.commit("signed tip"))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_new_branch_accepts_signed_tip_on_remote_unsigned_history(self):
        self.published_unsigned_commit()
        result = self.push(self.commit("signed tip"), remote="0" * 40)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_new_unsigned_commit_is_rejected(self):
        self.published_unsigned_commit()
        revision = self.commit("unsigned tip", signed=False)
        result = self.push(revision)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"commit {revision} is not cryptographically signed", result.stderr)

    def test_signed_tip_does_not_hide_unsigned_ancestor(self):
        revision = self.commit("unsigned ancestor", signed=False)
        result = self.push(self.commit("signed tip"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"commit {revision} is not cryptographically signed", result.stderr)

    def test_other_remote_does_not_exempt_unsigned_commit(self):
        revision = self.commit("other remote", signed=False)
        self.run_command("git", "update-ref", "refs/remotes/elsewhere/main", revision)
        self.run_command("git", "update-ref", "-d", "refs/remotes/origin/topic")
        result = self.push(self.commit("signed tip"), remote="0" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"commit {revision} is not cryptographically signed", result.stderr)

    def test_branch_deletion_is_allowed(self):
        result = self.push("0" * 40)
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
