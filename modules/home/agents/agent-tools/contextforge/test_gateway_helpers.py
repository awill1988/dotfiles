import importlib.util
import io
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest
from urllib.error import HTTPError
from urllib.parse import parse_qs, urlparse


def load_script(name):
    spec = importlib.util.spec_from_file_location(name, Path(__file__).parent / "scripts" / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class GatewayHelpersTest(unittest.TestCase):
    def test_cursor_pages_preserve_every_tool_and_authentication(self):
        requests = []
        pages = iter([
            {"tools": [{"id": str(i)} for i in range(100)], "nextCursor": "cursor+/="},
            {"tools": [{"id": "100"}], "nextCursor": None},
        ])

        def open_url(request, timeout):
            requests.append(request)
            return io.StringIO(json.dumps(next(pages)))

        result = load_script("list-resources").list_resources("http://localhost:4444", "tools", "test-token", open_url)
        self.assertEqual(len(result), 101)
        self.assertEqual(result[-1], {"id": "100"})
        self.assertEqual(parse_qs(urlparse(requests[1].full_url).query)["cursor"], ["cursor+/="])
        for request in requests:
            self.assertEqual(request.get_header("Authorization"), "Bearer test-token")

    def test_repeated_cursor_fails_instead_of_returning_partial_inventory(self):
        def open_url(request, timeout):
            return io.StringIO(json.dumps({"tools": [], "nextCursor": "same"}))

        with self.assertRaisesRegex(RuntimeError, "repeated"):
            load_script("list-resources").list_resources("http://localhost:4444", "tools", "test-token", open_url)

    def test_failed_page_does_not_become_empty_inventory(self):
        def open_url(request, timeout):
            raise HTTPError(request.full_url, 401, "unauthorized", {}, None)

        with self.assertRaises(HTTPError) as failure:
            load_script("list-resources").list_resources("http://localhost:4444", "tools", "test-token", open_url)
        failure.exception.close()

    def test_empty_header_credentials_are_missing(self):
        script = Path(__file__).parent / "scripts" / "sync-parse-toml.py"
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / "servers.toml"
            output = Path(directory) / "servers.json"
            config.write_text('[[servers]]\nname="fixture"\nurl="https://example.com/mcp"\nheaders={Authorization="Bearer $TEST_TOKEN"}\n')
            for environment in ({}, {"TEST_TOKEN": ""}):
                subprocess.run([sys.executable, str(script), str(config), str(output)], env=environment, check=True)
                self.assertEqual(json.loads(output.read_text())[0]["missing_headers"], ["TEST_TOKEN"])

    def test_secret_initialization_preserves_identity_and_permissions(self):
        initialize = load_script("init-secrets").initialize
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "secrets.env"
            initialize(path)
            initial = path.read_bytes()
            initialize(path)
            self.assertEqual(path.read_bytes(), initial)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            values = [line.split("=", 1)[1] for line in initial.decode().splitlines()]
            self.assertEqual(len(set(values)), 5)
            self.assertTrue(all(len(value) >= 64 for value in values))


if __name__ == "__main__":
    unittest.main()
