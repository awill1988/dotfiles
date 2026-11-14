import importlib.util
import json
import os
import stat
import tempfile
import unittest
from unittest import mock


def load_bridge_module():
    path = os.environ["BRIDGE_PY"]
    spec = importlib.util.spec_from_file_location("drive_mcp_bridge", path)
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class DriveMcpClientIsolationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.env = mock.patch.dict(os.environ, {"DRIVE_MCP_DIR": self.tmp.name}, clear=False)
        self.env.start()
        self.addCleanup(self.env.stop)
        self.bridge = load_bridge_module()

    def _write_src_client(self, cid: str, secret: str, project_id: str) -> str:
        fd, path = tempfile.mkstemp(dir=self.tmp.name, suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(
                {
                    "installed": {
                        "client_id": cid,
                        "client_secret": secret,
                        "project_id": project_id,
                    }
                },
                fh,
            )
        return path

    def test_client_precedence_and_strict_domain_isolation(self):
        arro_src = self._write_src_client("arro-cid", "arro-sec", "arro-finance-001")
        pers_dom_src = self._write_src_client("dom-cid", "dom-sec", "williams-dom-proj")
        pers_exact_src = self._write_src_client("exact-cid", "exact-sec", "williams-exact-proj")

        self.assertEqual(self.bridge.cmd_client(["@arrofinance.com", arro_src]), 0)
        dest = os.path.join(self.tmp.name, "clients", "@arrofinance.com.json")
        mode = stat.S_IMODE(os.stat(dest).st_mode)
        self.assertEqual(mode, 0o600)

        # Unconfigured domain must fail rather than leaking @arrofinance.com's client
        with self.assertRaisesRegex(RuntimeError, r"no oauth client for founder@yourmood\.ai"):
            self.bridge.load_client("founder@yourmood.ai")

        # Domain match works
        self.assertEqual(self.bridge.load_client("adam@arrofinance.com")["project_id"], "arro-finance-001")

        # Exact email overrides @domain, which overrides legacy client.json
        legacy_path = os.path.join(self.tmp.name, "client.json")
        with open(legacy_path, "w", encoding="utf-8") as fh:
            json.dump({"installed": {"client_id": "leg", "client_secret": "leg-s", "project_id": "legacy"}}, fh)

        self.assertEqual(self.bridge.load_client("founder@yourmood.ai")["project_id"], "legacy")
        self.bridge.cmd_client(["@williams.engineer", pers_dom_src])
        self.assertEqual(self.bridge.load_client("adam@williams.engineer")["project_id"], "williams-dom-proj")
        self.bridge.cmd_client(["adam@williams.engineer", pers_exact_src])
        self.assertEqual(self.bridge.load_client("adam@williams.engineer")["project_id"], "williams-exact-proj")

    def test_dispatch_single_rpc_isolates_project_header_and_refresh_client(self):
        arro_src = self._write_src_client("arro-cid", "arro-sec", "arro-finance-001")
        pers_src = self._write_src_client("pers-cid", "pers-sec", "williams-personal-001")
        self.bridge.cmd_client(["@arrofinance.com", arro_src])
        self.bridge.cmd_client(["@williams.engineer", pers_src])

        self.bridge.save_tokens(
            "adam@arrofinance.com",
            {"access_token": "tok-arro", "refresh_token": "rt-arro", "expires_in": 3600},
        )
        self.bridge.save_tokens(
            "adam@williams.engineer",
            {"access_token": "tok-pers", "refresh_token": "rt-pers", "expires_at": 0},
        )

        captured_contexts = []

        def fake_post(msg, ctx, session_key=None, retry_on_401=True):
            captured_contexts.append((dict(ctx), session_key))
            return {"jsonrpc": "2.0", "id": msg["id"], "result": {"ok": True}}

        def fake_refresh(email, tokens, client):
            self.assertEqual(email, "adam@williams.engineer")
            self.assertEqual(client["client_id"], "pers-cid")
            return {"access_token": "tok-pers-refreshed", "refresh_token": "rt-pers", "expires_in": 3600}

        with mock.patch.object(self.bridge, "post", side_effect=fake_post), mock.patch.object(
            self.bridge, "refresh_access", side_effect=fake_refresh
        ):
            r1 = self.bridge.dispatch_single_rpc(
                {"jsonrpc": "2.0", "id": 1, "method": "tools/list"},
                "adam@arrofinance.com",
                "sid-1",
            )
            r2 = self.bridge.dispatch_single_rpc(
                {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
                "adam@williams.engineer",
                "sid-1",
            )

        self.assertIn("result", r1)
        self.assertIn("result", r2)
        self.assertEqual(captured_contexts[0][0]["project_id"], "arro-finance-001")
        self.assertEqual(captured_contexts[0][0]["access_token"], "tok-arro")
        self.assertEqual(captured_contexts[1][0]["project_id"], "williams-personal-001")
        self.assertEqual(captured_contexts[1][0]["access_token"], "tok-pers-refreshed")

    def test_login_aborts_on_principal_mismatch(self):
        pers_src = self._write_src_client("pers-cid", "pers-sec", "williams-personal-001")
        self.bridge.cmd_client(["@williams.engineer", pers_src])

        with mock.patch.object(
            self.bridge,
            "run_oauth_flow",
            return_value={"access_token": "tok", "refresh_token": "rt", "expires_in": 3600},
        ), mock.patch.object(
            self.bridge,
            "fetch_userinfo",
            return_value={"email": "wrong@arrofinance.com"},
        ):
            with self.assertRaisesRegex(RuntimeError, r"authenticated as wrong@arrofinance\.com, expected adam@williams\.engineer"):
                self.bridge.cmd_login(["adam@williams.engineer"])


if __name__ == "__main__":
    unittest.main()
