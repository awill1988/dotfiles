"""drive-mcp bridge + account manager.

modes (selected by argv[1]):
  bridge    stdio<->http mcp bridge for drivemcp.googleapis.com (default)
  serve     local streamable-http mcp server on 127.0.0.1:4445/mcp (per-request X-Drive-Account)
  login     run oauth installed-app flow, save tokens for an account
  client    register an oauth client json for an <email> or @<domain>
  clients   list registered oauth clients and their gcp project ids
  use       set the active account
  list      list cached accounts
  current   print the active account

state lives under $DRIVE_MCP_DIR (default ~/.config/drive-mcp):
  clients/<email>.json    per-account oauth client (0600, highest precedence)
  clients/@<domain>.json  per-domain oauth client (0600, second precedence)
  client.json             legacy fallback oauth client
  tokens/<email>.json     refresh + access tokens per account (0600)
  active                  text file: email of active account
"""

import argparse
import http.server
import json
import os
import secrets
import socket
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import webbrowser

ENDPOINT = os.environ.get("DRIVE_MCP_URL", "https://drivemcp.googleapis.com/mcp/v1")
SCOPES = [
    "https://www.googleapis.com/auth/drive.readonly",
    "https://www.googleapis.com/auth/drive.file",
    "https://www.googleapis.com/auth/userinfo.email",
    "openid",
]
HTTP_TIMEOUT = 60
TOKEN_REFRESH_LEEWAY = 120  # seconds before expiry to refresh

def config_dir() -> str:
    return os.environ.get("DRIVE_MCP_DIR") or os.path.expanduser("~/.config/drive-mcp")


def client_file() -> str:
    return os.path.join(config_dir(), "client.json")


def clients_dir() -> str:
    return os.path.join(config_dir(), "clients")


def tokens_dir() -> str:
    return os.path.join(config_dir(), "tokens")


def active_file() -> str:
    return os.path.join(config_dir(), "active")


CONFIG_DIR = config_dir()
CLIENT_FILE = client_file()
CLIENTS_DIR = clients_dir()
TOKENS_DIR = tokens_dir()
ACTIVE_FILE = active_file()

_locks_guard = threading.Lock()
_account_locks: dict[str, threading.Lock] = {}

_sessions_guard = threading.Lock()
_upstream_sessions: dict[tuple[str, str], str] = {}


def log(msg: str) -> None:
    sys.stderr.write(f"drive-mcp: {msg}\n")
    sys.stderr.flush()


def account_lock(email: str) -> threading.Lock:
    with _locks_guard:
        lock = _account_locks.get(email)
        if lock is None:
            lock = threading.Lock()
            _account_locks[email] = lock
        return lock


def get_upstream_session(key: tuple[str, str]) -> str | None:
    with _sessions_guard:
        return _upstream_sessions.get(key)


def set_upstream_session(key: tuple[str, str], sid: str) -> None:
    with _sessions_guard:
        _upstream_sessions[key] = sid


def clear_upstream_session_by_client_sid(client_sid: str) -> None:
    with _sessions_guard:
        stale = [k for k in _upstream_sessions if k[1] == client_sid]
        for k in stale:
            _upstream_sessions.pop(k, None)


def normalize_client_target(target: str) -> str:
    norm = target.strip().lower()
    if not norm or "/" in norm or ".." in norm or "@" not in norm:
        raise RuntimeError(
            f"invalid client target '{target}'; expected <email> or @<domain>"
        )
    local, domain = norm.split("@", 1)
    if not domain or "." not in domain or ("@" in domain):
        raise RuntimeError(
            f"invalid client target '{target}'; expected <email> or @<domain>"
        )
    if norm.startswith("@"):
        return f"@{domain}"
    if not local:
        raise RuntimeError(
            f"invalid client target '{target}'; expected <email> or @<domain>"
        )
    return f"{local}@{domain}"


def client_path(target: str) -> str:
    norm = normalize_client_target(target)
    return os.path.join(clients_dir(), f"{norm}.json")


def parse_client_file(path: str) -> dict:
    if not os.path.isfile(path):
        raise RuntimeError(f"oauth client file not found: {path}")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            data = json.load(fh)
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"invalid json in oauth client {path}: {exc}")
    if not isinstance(data, dict):
        raise RuntimeError(f"{path} must contain a json object")
    inner = data.get("installed") or data.get("web") or data
    if not isinstance(inner, dict):
        raise RuntimeError(f"{path} missing installed/web client object")
    cid = inner.get("client_id")
    secret = inner.get("client_secret")
    if not cid or not secret:
        raise RuntimeError(f"{path} missing client_id/client_secret")
    return {
        "client_id": cid,
        "client_secret": secret,
        "project_id": inner.get("project_id", ""),
    }


def save_client(target: str, src_path: str) -> tuple[str, dict]:
    norm = normalize_client_target(target)
    parsed = parse_client_file(src_path)
    with open(src_path, "r", encoding="utf-8") as fh:
        raw_data = json.load(fh)
    cdir = clients_dir()
    os.makedirs(cdir, exist_ok=True)
    dest = os.path.join(cdir, f"{norm}.json")
    tmp = dest + f".{secrets.token_hex(4)}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        json.dump(raw_data, fh)
    os.replace(tmp, dest)
    return dest, parsed


def resolve_client_file(email: str | None) -> str | None:
    if email and "@" in email:
        norm = normalize_client_target(email)
        exact = os.path.join(clients_dir(), f"{norm}.json")
        if os.path.isfile(exact):
            return exact
        domain = "@" + norm.split("@", 1)[1]
        by_domain = os.path.join(clients_dir(), f"{domain}.json")
        if os.path.isfile(by_domain):
            return by_domain
    fallback = client_file()
    if os.path.isfile(fallback):
        return fallback
    return None


def load_client(email: str | None = None) -> dict:
    path = resolve_client_file(email)
    if not path:
        if email and "@" in email:
            domain = "@" + email.strip().split("@", 1)[1].lower()
            raise RuntimeError(
                f"no oauth client for {email}; run "
                f"`drive-account client {domain} <client.json>` first"
            )
        raise RuntimeError(
            f"oauth client missing at {client_file()}; register one with "
            "`drive-account client @<domain> <client.json>`"
        )
    return parse_client_file(path)


def token_path(email: str) -> str:
    safe = email.replace("/", "_").replace("..", "_")
    return os.path.join(tokens_dir(), f"{safe}.json")


def list_accounts() -> list[str]:
    tdir = tokens_dir()
    if not os.path.isdir(tdir):
        return []
    out = []
    for name in sorted(os.listdir(tdir)):
        if name.endswith(".json"):
            out.append(name[:-5])
    return out


def read_active() -> str | None:
    env = os.environ.get("DRIVE_ACCOUNT")
    if env:
        return env
    af = active_file()
    if os.path.isfile(af):
        with open(af, "r", encoding="utf-8") as fh:
            value = fh.read().strip()
            return value or None
    accounts = list_accounts()
    return accounts[0] if accounts else None


def write_active(email: str) -> None:
    os.makedirs(config_dir(), exist_ok=True)
    af = active_file()
    tmp = af + f".{secrets.token_hex(4)}.tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(email + "\n")
    os.replace(tmp, af)


def save_tokens(email: str, payload: dict) -> None:
    os.makedirs(tokens_dir(), exist_ok=True)
    payload = dict(payload)
    if "expires_at" not in payload and "expires_in" in payload:
        payload["expires_at"] = time.time() + int(payload["expires_in"]) - TOKEN_REFRESH_LEEWAY
    payload["email"] = email
    path = token_path(email)
    tmp = path + f".{secrets.token_hex(4)}.tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(payload, fh)
    os.replace(tmp, path)


def load_tokens(email: str) -> dict:
    path = token_path(email)
    if not os.path.isfile(path):
        raise RuntimeError(
            f"no tokens for {email}; run `drive-account login {email}` first"
        )
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def refresh_access(email: str, tokens: dict, client: dict) -> dict:
    rt = tokens.get("refresh_token")
    if not rt:
        raise RuntimeError(f"no refresh_token cached for {email}; re-run login")
    body = urllib.parse.urlencode({
        "client_id": client["client_id"],
        "client_secret": client["client_secret"],
        "refresh_token": rt,
        "grant_type": "refresh_token",
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            payload = json.loads(resp.read())
    except urllib.error.HTTPError as exc:
        text = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"refresh failed for {email}: http {exc.code}: {text[:200]}")
    payload.setdefault("refresh_token", rt)
    save_tokens(email, payload)
    return payload


def current_access_token(email: str, client: dict, force_refresh: bool = False) -> str:
    with account_lock(email):
        tokens = load_tokens(email)
        if force_refresh or time.time() >= float(tokens.get("expires_at", 0)):
            tokens = refresh_access(email, tokens, client)
        return tokens["access_token"]


def fetch_userinfo(access_token: str) -> dict:
    req = urllib.request.Request(
        "https://openidconnect.googleapis.com/v1/userinfo",
        headers={"Authorization": f"Bearer {access_token}"},
    )
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read())


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def run_oauth_flow(client: dict, hint: str | None) -> dict:
    port = free_port()
    redirect_uri = f"http://127.0.0.1:{port}"
    state = secrets.token_urlsafe(16)
    holder: dict = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            qs = urllib.parse.urlparse(self.path).query
            params = urllib.parse.parse_qs(qs)
            holder["code"] = (params.get("code") or [None])[0]
            holder["state"] = (params.get("state") or [None])[0]
            holder["error"] = (params.get("error") or [None])[0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            body = b"<h2>drive-mcp authorized.</h2><p>you can close this tab.</p>"
            if holder["error"]:
                body = f"<h2>auth error: {holder['error']}</h2>".encode("utf-8")
            self.wfile.write(body)

        def log_message(self, *_args, **_kwargs):
            return

    server = http.server.HTTPServer(("127.0.0.1", port), Handler)
    threading.Thread(target=server.handle_request, daemon=True).start()

    auth_params = {
        "client_id": client["client_id"],
        "redirect_uri": redirect_uri,
        "response_type": "code",
        "scope": " ".join(SCOPES),
        "access_type": "offline",
        "prompt": "consent",
        "state": state,
    }
    if hint:
        auth_params["login_hint"] = hint
    auth_url = "https://accounts.google.com/o/oauth2/v2/auth?" + urllib.parse.urlencode(auth_params)

    log(f"opening browser for oauth (account hint: {hint or '<any>'})")
    log(f"if no browser opens, visit: {auth_url}")
    webbrowser.open(auth_url)

    deadline = time.time() + 300
    while "code" not in holder and time.time() < deadline:
        time.sleep(0.1)
    server.server_close()

    if holder.get("error"):
        raise RuntimeError(f"oauth error: {holder['error']}")
    if not holder.get("code"):
        raise RuntimeError("oauth flow timed out (no code received)")
    if holder.get("state") != state:
        raise RuntimeError("oauth state mismatch")

    body = urllib.parse.urlencode({
        "code": holder["code"],
        "client_id": client["client_id"],
        "client_secret": client["client_secret"],
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code",
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/token",
        data=body,
        headers={"Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read())


def cmd_client(argv: list[str]) -> int:
    if len(argv) != 2:
        log("usage: drive-account client <email|@domain> <client.json>")
        return 2
    dest, parsed = save_client(argv[0], argv[1])
    proj = parsed.get("project_id") or "<none>"
    log(f"saved oauth client for {normalize_client_target(argv[0])} (project: {proj}) -> {dest}")
    return 0


def list_clients() -> list[tuple[str, str]]:
    out: list[tuple[str, str]] = []
    cdir = clients_dir()
    if os.path.isdir(cdir):
        for name in sorted(os.listdir(cdir)):
            if not name.endswith(".json"):
                continue
            target = name[:-5]
            path = os.path.join(cdir, name)
            try:
                parsed = parse_client_file(path)
                out.append((target, parsed.get("project_id") or ""))
            except RuntimeError:
                out.append((target, "<invalid>"))
    fallback = client_file()
    if os.path.isfile(fallback):
        try:
            parsed = parse_client_file(fallback)
            out.append(("default", parsed.get("project_id") or ""))
        except RuntimeError:
            out.append(("default", "<invalid>"))
    return out


def cmd_clients(_argv: list[str]) -> int:
    entries = list_clients()
    if not entries:
        log("no oauth clients configured (run `drive-account client @<domain> <client.json>`)")
        return 0
    for target, proj in entries:
        suffix = f"\t{proj}" if proj else ""
        sys.stdout.write(f"{target}{suffix}\n")
    return 0


def cmd_login(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="drive-account login")
    parser.add_argument("email", nargs="?", help="account email hint")
    parser.add_argument("--client", dest="client_json", help="oauth client json path to register")
    opts = parser.parse_args(argv)
    hint = opts.email.strip() if opts.email else None

    if opts.client_json:
        if hint:
            save_client(hint, opts.client_json)
            client = load_client(hint)
        else:
            client = parse_client_file(opts.client_json)
    else:
        client = load_client(hint)

    payload = run_oauth_flow(client, hint)
    info = fetch_userinfo(payload["access_token"])
    email = info.get("email")
    if not email:
        raise RuntimeError("could not resolve email from userinfo")
    if hint and email.strip().lower() != hint.lower():
        raise RuntimeError(
            f"authenticated as {email}, expected {hint}; aborting token save"
        )
    if opts.client_json and not hint:
        save_client(email, opts.client_json)
    save_tokens(email, payload)
    if not os.path.isfile(active_file()):
        write_active(email)
    log(f"saved tokens for {email}")
    log(f"active account: {read_active()}")
    return 0


def cmd_use(argv: list[str]) -> int:
    if not argv:
        log("usage: drive-account use <email>")
        return 2
    email = argv[0]
    if email not in list_accounts():
        log(f"no cached tokens for {email}; run `drive-account login {email}` first")
        return 1
    write_active(email)
    log(f"active account: {email}")
    return 0


def cmd_list(_argv: list[str]) -> int:
    active = read_active()
    accounts = list_accounts()
    if not accounts:
        log("no accounts (run `drive-account login` to add one)")
        return 0
    for email in accounts:
        marker = "*" if email == active else " "
        sys.stdout.write(f"{marker} {email}\n")
    return 0


def cmd_current(_argv: list[str]) -> int:
    active = read_active()
    if active:
        sys.stdout.write(active + "\n")
        return 0
    log("no active account")
    return 1


def parse_sse(payload: bytes) -> dict | None:
    last_json = None
    for line in payload.decode("utf-8", errors="replace").splitlines():
        if line.startswith("data:"):
            data = line[5:].strip()
            if data:
                try:
                    last_json = json.loads(data)
                except json.JSONDecodeError:
                    continue
    return last_json


def post(
    message: dict,
    ctx: dict,
    session_key: tuple[str, str] | None = None,
    retry_on_401: bool = True,
) -> dict | None:
    is_init = isinstance(message, dict) and message.get("method") == "initialize"
    body = json.dumps(message).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Authorization": f"Bearer {ctx['access_token']}",
    }
    if ctx.get("project_id"):
        headers["X-Goog-User-Project"] = ctx["project_id"]
    if session_key and not is_init:
        upstream_sid = get_upstream_session(session_key)
        if upstream_sid:
            headers["Mcp-Session-Id"] = upstream_sid

    req = urllib.request.Request(ENDPOINT, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            sid = resp.headers.get("Mcp-Session-Id")
            if sid and session_key:
                set_upstream_session(session_key, sid)
            ctype = (resp.headers.get("Content-Type") or "").lower()
            data = resp.read()
            if not data:
                return None
            if ctype.startswith("text/event-stream"):
                return parse_sse(data)
            try:
                return json.loads(data)
            except json.JSONDecodeError:
                return None
    except urllib.error.HTTPError as exc:
        if exc.code == 401 and retry_on_401:
            try:
                ctx["access_token"] = current_access_token(
                    ctx["email"], ctx["client"], force_refresh=True
                )
            except RuntimeError as token_exc:
                return error_frame(message, -32000, str(token_exc))
            return post(message, ctx, session_key=session_key, retry_on_401=False)
        text = exc.read().decode("utf-8", errors="replace")
        return error_frame(message, -32000, f"http {exc.code}: {text[:300]}")
    except urllib.error.URLError as exc:
        return error_frame(message, -32000, f"network error: {exc.reason}")


def error_frame(message: dict, code: int, text: str) -> dict | None:
    if not isinstance(message, dict):
        log(text)
        return None
    msg_id = message.get("id")
    if msg_id is None:
        log(text)
        return None
    return {"jsonrpc": "2.0", "id": msg_id, "error": {"code": code, "message": text}}


def cmd_bridge(_argv: list[str]) -> int:
    email = read_active()
    if not email:
        log("no active drive account; run `drive-account login` first")
        return 1
    try:
        client = load_client(email)
        access_token = current_access_token(email, client)
    except RuntimeError as exc:
        log(str(exc))
        return 1

    ctx = {
        "client": client,
        "email": email,
        "access_token": access_token,
        "project_id": client.get("project_id", ""),
    }
    session_key = (email, "__stdio__")
    log(f"active account: {email}")

    for raw in sys.stdin:
        line = raw.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            log(f"invalid json on stdin: {line[:120]}")
            continue
        try:
            ctx["access_token"] = current_access_token(email, client)
            resp = post(msg, ctx, session_key=session_key)
        except RuntimeError as exc:
            resp = error_frame(msg, -32000, str(exc))
        if resp is None:
            continue
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
    return 0


class ReusableThreadingHTTPServer(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


def dispatch_single_rpc(msg: dict, header_account: str, client_sid: str) -> dict | None:
    method = msg.get("method")
    if method == "ping":
        return {"jsonrpc": "2.0", "id": msg.get("id", 0), "result": {}}

    # Strict profile isolation: never fall back to `active` when X-Drive-Account is supplied.
    if header_account:
        email = header_account
    else:
        email = read_active()
        if not email:
            return error_frame(
                msg, -32000, "no active drive account; run `drive-account login` first"
            )

    try:
        client = load_client(email)
        access_token = current_access_token(email, client)
    except RuntimeError as exc:
        return error_frame(msg, -32000, str(exc))

    ctx = {
        "client": client,
        "email": email,
        "access_token": access_token,
        "project_id": client.get("project_id", ""),
    }
    return post(msg, ctx, session_key=(email, client_sid))


def cmd_serve(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="drive-mcp serve")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4445)
    opts = parser.parse_args(argv)

    class McpHandler(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def _write_json(
            self, status: int, payload: dict | list, session_id: str | None = None
        ) -> None:
            raw = json.dumps(payload).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            if session_id:
                self.send_header("Mcp-Session-Id", session_id)
            self.end_headers()
            self.wfile.write(raw)

        def _write_empty(self, status: int, extra_headers: dict[str, str] | None = None) -> None:
            self.send_response(status)
            self.send_header("Content-Length", "0")
            for k, v in (extra_headers or {}).items():
                self.send_header(k, v)
            self.end_headers()

        def do_GET(self):
            path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
            if path == "/health":
                self._write_json(200, {"status": "ok", "accounts": list_accounts()})
                return
            if path == "/mcp":
                self._write_empty(405, {"Allow": "POST, DELETE"})
                return
            self._write_empty(404)

        def do_DELETE(self):
            path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
            if path != "/mcp":
                self._write_empty(404)
                return
            sid = (self.headers.get("Mcp-Session-Id") or "").strip()
            if sid:
                clear_upstream_session_by_client_sid(sid)
            self._write_empty(200)

        def do_POST(self):
            path = urllib.parse.urlparse(self.path).path.rstrip("/") or "/"
            if path != "/mcp":
                self._write_empty(404)
                return

            length = int(self.headers.get("Content-Length") or "0")
            raw = self.rfile.read(length) if length > 0 else b""
            if not raw.strip():
                self._write_json(200, {})
                return

            try:
                payload = json.loads(raw)
            except json.JSONDecodeError:
                self._write_json(
                    400,
                    {"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "parse error"}},
                )
                return

            # Empty object probe used by contextforge-mcp-sync readiness checks
            if payload == {}:
                self._write_json(200, {})
                return

            header_account = (self.headers.get("X-Drive-Account") or "").strip()
            client_sid = (self.headers.get("Mcp-Session-Id") or "").strip()

            if isinstance(payload, dict):
                if payload.get("method") == "initialize" or not client_sid:
                    client_sid = client_sid or secrets.token_urlsafe(16)
                is_request = "id" in payload and payload.get("id") is not None
                resp = dispatch_single_rpc(payload, header_account, client_sid)
                if not is_request:
                    self._write_empty(202, {"Mcp-Session-Id": client_sid})
                    return
                if resp is None:
                    resp = error_frame(payload, -32603, "empty upstream response")
                self._write_json(200, resp, session_id=client_sid)
                return

            if isinstance(payload, list):
                client_sid = client_sid or secrets.token_urlsafe(16)
                responses = []
                for item in payload:
                    if not isinstance(item, dict):
                        continue
                    is_request = "id" in item and item.get("id") is not None
                    resp = dispatch_single_rpc(item, header_account, client_sid)
                    if is_request:
                        responses.append(
                            resp if resp is not None else error_frame(item, -32603, "empty upstream response")
                        )
                if not responses:
                    self._write_empty(202, {"Mcp-Session-Id": client_sid})
                    return
                self._write_json(200, responses, session_id=client_sid)
                return

            self._write_json(
                400,
                {"jsonrpc": "2.0", "id": None, "error": {"code": -32600, "message": "invalid request"}},
            )

        def log_message(self, *_args, **_kwargs):
            return

    server = ReusableThreadingHTTPServer((opts.host, opts.port), McpHandler)
    log(f"listening on http://{opts.host}:{opts.port}/mcp")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


COMMANDS = {
    "bridge": cmd_bridge,
    "serve": cmd_serve,
    "login": cmd_login,
    "client": cmd_client,
    "clients": cmd_clients,
    "use": cmd_use,
    "list": cmd_list,
    "current": cmd_current,
}


def main() -> int:
    args = sys.argv[1:]
    cmd = args[0] if args else "bridge"
    handler = COMMANDS.get(cmd)
    if not handler:
        log(f"unknown command: {cmd}")
        log(f"usage: drive-mcp [{'|'.join(COMMANDS)}] ...")
        return 2
    try:
        return handler(args[1:])
    except RuntimeError as exc:
        log(str(exc))
        return 1
    except KeyboardInterrupt:
        return 130


if __name__ == "__main__":
    sys.exit(main())
