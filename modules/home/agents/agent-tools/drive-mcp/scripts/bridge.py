"""drive-mcp bridge + account manager.

modes (selected by argv[1]):
  bridge    stdio<->http mcp bridge for drivemcp.googleapis.com (default)
  login     run oauth installed-app flow, save tokens for an account
  use       set the active account
  list      list cached accounts
  current   print the active account

state lives under $DRIVE_MCP_DIR (default ~/.config/drive-mcp):
  client.json           oauth client (downloaded from cloud console)
  tokens/<email>.json   refresh + access tokens per account
  active                text file: email of active account
"""

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

CONFIG_DIR = os.environ.get("DRIVE_MCP_DIR") or os.path.expanduser("~/.config/drive-mcp")
CLIENT_FILE = os.path.join(CONFIG_DIR, "client.json")
TOKENS_DIR = os.path.join(CONFIG_DIR, "tokens")
ACTIVE_FILE = os.path.join(CONFIG_DIR, "active")

_session_id = None


def log(msg: str) -> None:
    sys.stderr.write(f"drive-mcp: {msg}\n")
    sys.stderr.flush()


def load_client() -> dict:
    if not os.path.isfile(CLIENT_FILE):
        raise RuntimeError(
            f"oauth client missing at {CLIENT_FILE}; create a desktop oauth client "
            "in google cloud console and place the json there"
        )
    with open(CLIENT_FILE, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    inner = data.get("installed") or data.get("web") or data
    cid = inner.get("client_id")
    secret = inner.get("client_secret")
    if not cid or not secret:
        raise RuntimeError(f"client.json missing client_id/client_secret")
    return {
        "client_id": cid,
        "client_secret": secret,
        "project_id": inner.get("project_id", ""),
    }


def token_path(email: str) -> str:
    safe = email.replace("/", "_").replace("..", "_")
    return os.path.join(TOKENS_DIR, f"{safe}.json")


def list_accounts() -> list[str]:
    if not os.path.isdir(TOKENS_DIR):
        return []
    out = []
    for name in sorted(os.listdir(TOKENS_DIR)):
        if name.endswith(".json"):
            out.append(name[:-5])
    return out


def read_active() -> str | None:
    env = os.environ.get("DRIVE_ACCOUNT")
    if env:
        return env
    if os.path.isfile(ACTIVE_FILE):
        with open(ACTIVE_FILE, "r", encoding="utf-8") as fh:
            value = fh.read().strip()
            return value or None
    accounts = list_accounts()
    return accounts[0] if accounts else None


def write_active(email: str) -> None:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    tmp = ACTIVE_FILE + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(email + "\n")
    os.replace(tmp, ACTIVE_FILE)


def save_tokens(email: str, payload: dict) -> None:
    os.makedirs(TOKENS_DIR, exist_ok=True)
    payload = dict(payload)
    if "expires_at" not in payload and "expires_in" in payload:
        payload["expires_at"] = time.time() + int(payload["expires_in"]) - TOKEN_REFRESH_LEEWAY
    payload["email"] = email
    path = token_path(email)
    tmp = path + ".tmp"
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
        raise RuntimeError(f"refresh failed: http {exc.code}: {text[:200]}")
    payload.setdefault("refresh_token", rt)
    save_tokens(email, payload)
    return payload


def current_access_token(email: str, client: dict) -> str:
    tokens = load_tokens(email)
    if time.time() >= float(tokens.get("expires_at", 0)):
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


def cmd_login(argv: list[str]) -> int:
    hint = argv[0] if argv else None
    client = load_client()
    payload = run_oauth_flow(client, hint)
    info = fetch_userinfo(payload["access_token"])
    email = info.get("email")
    if not email:
        raise RuntimeError("could not resolve email from userinfo")
    save_tokens(email, payload)
    if not os.path.isfile(ACTIVE_FILE):
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
    for line in payload.decode("utf-8", errors="replace").splitlines():
        if line.startswith("data:"):
            data = line[5:].strip()
            if data:
                try:
                    return json.loads(data)
                except json.JSONDecodeError:
                    return None
    return None


def post(message: dict, ctx: dict, retry_on_401: bool = True) -> dict | None:
    global _session_id
    body = json.dumps(message).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
        "Authorization": f"Bearer {ctx['access_token']}",
    }
    if ctx.get("project_id"):
        headers["X-Goog-User-Project"] = ctx["project_id"]
    if _session_id:
        headers["Mcp-Session-Id"] = _session_id

    req = urllib.request.Request(ENDPOINT, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT) as resp:
            sid = resp.headers.get("Mcp-Session-Id")
            if sid:
                _session_id = sid
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
                tokens = refresh_access(ctx["email"], load_tokens(ctx["email"]), ctx["client"])
                ctx["access_token"] = tokens["access_token"]
            except RuntimeError as token_exc:
                return error_frame(message, -32000, str(token_exc))
            return post(message, ctx, retry_on_401=False)
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
    try:
        client = load_client()
    except RuntimeError as exc:
        log(str(exc))
        return 1
    email = read_active()
    if not email:
        log("no active drive account; run `drive-account login` first")
        return 1
    try:
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
            resp = post(msg, ctx)
        except RuntimeError as exc:
            resp = error_frame(msg, -32000, str(exc))
        if resp is None:
            continue
        sys.stdout.write(json.dumps(resp) + "\n")
        sys.stdout.flush()
    return 0


COMMANDS = {
    "bridge": cmd_bridge,
    "login": cmd_login,
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
