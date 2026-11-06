#!/usr/bin/env python3

import asyncio
import atexit
from collections.abc import Awaitable, Callable
import json
import os
import re
import signal
import socket
import subprocess
import sys
import tempfile
import time
from urllib.parse import quote, urlsplit, urlunsplit

import psycopg
from psycopg.rows import dict_row

import mcp.types as types
from mcp.server.lowlevel import NotificationOptions, Server
from mcp.server.lowlevel.helper_types import ReadResourceContents
from mcp.server.models import InitializationOptions
from mcp.server.stdio import stdio_server

SERVER_NAME = "contextforge/postgres"
SERVER_VERSION = "0.1.0"
SCHEMA_PATH = "schema"

DEFAULT_AWS_PROFILE = "arro-production"
DEFAULT_AWS_REGION = "us-west-2"
DEFAULT_DB_NAME = "galileoEvents"
DEFAULT_REPLICA_INSTANCE_ID = "galileo-api-read-replica"
DEFAULT_WRITER_INSTANCE_ID = "arro-prod-galileoapinfra-postgreswithbastiondbins-fel2wuhp6l1y"
DEFAULT_BASTION_FILTER = "*PostgresWithBastion*"
DEFAULT_MCP_SECRET_ID = "arro-production/galileo-db/svc-mcp"
DEFAULT_MASTER_SECRET_ID = "arro/prod/galileo/galileo-rds-password"
DEFAULT_SSM_DOCUMENT = "AWS-StartPortForwardingSessionToRemoteHost"
IAM_TOKEN_TTL_SECONDS = 600


def _is_port_open(host: str, port: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=1.0):
            return True
    except OSError:
        return False


def _pick_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


class SSMTunnelManager:
    def __init__(self, explicit_url: str | None = None) -> None:
        self._explicit_url = explicit_url.strip() if explicit_url else None
        self.aws_profile = os.environ.get("AWS_PROFILE", DEFAULT_AWS_PROFILE)
        self.aws_region = os.environ.get("AWS_REGION", DEFAULT_AWS_REGION)
        self.db_name = os.environ.get("POSTGRES_DB", DEFAULT_DB_NAME)
        self.bastion_filter = os.environ.get("POSTGRES_BASTION_TAG_FILTER", DEFAULT_BASTION_FILTER)
        self.ssm_document = os.environ.get("POSTGRES_SSM_DOCUMENT", DEFAULT_SSM_DOCUMENT)
        self._lock = asyncio.Lock()
        self._proc: subprocess.Popen[bytes] | None = None
        self._local_port: int | None = None
        self._rds_host: str | None = None
        self._log_path: str | None = None
        self._cached_creds: tuple[str, str, str, float | None] | None = None

    def _aws_cmd(self, args: list[str]) -> list[str]:
        cmd = ["aws"]
        if self.aws_profile:
            cmd.extend(["--profile", self.aws_profile])
        if self.aws_region:
            cmd.extend(["--region", self.aws_region])
        cmd.extend(args)
        return cmd

    def _run_aws(self, args: list[str], timeout: float = 20.0) -> str:
        result = subprocess.run(
            self._aws_cmd(args),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        if result.returncode != 0:
            stderr = result.stderr.strip() or result.stdout.strip()
            raise RuntimeError(f"aws {' '.join(args[:2])} failed (profile={self.aws_profile}): {stderr}")
        return result.stdout.strip()

    def _resolve_bastion_id(self) -> str:
        bastion = self._run_aws(
            [
                "ec2",
                "describe-instances",
                "--filters",
                f"Name=tag:Name,Values={self.bastion_filter}",
                "Name=instance-state-name,Values=running",
                "--query",
                "Reservations[0].Instances[0].InstanceId",
                "--output",
                "text",
            ]
        )
        if not bastion or bastion == "None":
            raise RuntimeError(
                f"no running EC2 bastion matching tag:Name={self.bastion_filter} in {self.aws_region} "
                f"(profile={self.aws_profile})"
            )
        return bastion

    def _resolve_rds_endpoint(self) -> str:
        configured_id = os.environ.get("POSTGRES_RDS_INSTANCE_ID")
        candidate_ids = (
            [configured_id]
            if configured_id
            else [DEFAULT_REPLICA_INSTANCE_ID, DEFAULT_WRITER_INSTANCE_ID]
        )
        last_err: Exception | None = None
        for instance_id in candidate_ids:
            try:
                host = self._run_aws(
                    [
                        "rds",
                        "describe-db-instances",
                        "--db-instance-identifier",
                        instance_id,
                        "--query",
                        "DBInstances[0].Endpoint.Address",
                        "--output",
                        "text",
                    ]
                )
                if host and host != "None":
                    return host
            except Exception as err:
                last_err = err
        raise RuntimeError(f"unable to resolve RDS endpoint for {candidate_ids}: {last_err}")

    def _resolve_credentials(self, rds_host: str) -> tuple[str, str, str]:
        now = time.monotonic()
        if self._cached_creds is not None:
            user, password, dbname, expires_at = self._cached_creds
            if expires_at is None or now < expires_at:
                return user, password, dbname

        env_user = os.environ.get("POSTGRES_USER")
        env_password = os.environ.get("POSTGRES_PASSWORD")
        if env_user and env_password:
            self._cached_creds = (env_user, env_password, self.db_name, None)
            return env_user, env_password, self.db_name

        secret_ids = []
        custom_secret = os.environ.get("POSTGRES_SECRET_ID")
        if custom_secret:
            secret_ids.append(custom_secret)
        else:
            secret_ids.extend([DEFAULT_MCP_SECRET_ID, DEFAULT_MASTER_SECRET_ID])

        for secret_id in secret_ids:
            try:
                secret_str = self._run_aws(
                    [
                        "secretsmanager",
                        "get-secret-value",
                        "--secret-id",
                        secret_id,
                        "--query",
                        "SecretString",
                        "--output",
                        "text",
                    ]
                )
                if not secret_str or secret_str == "None":
                    continue
                try:
                    payload = json.loads(secret_str)
                    if isinstance(payload, dict) and payload.get("password"):
                        user = str(payload.get("username") or "dbuser")
                        password = str(payload["password"])
                        dbname = str(payload.get("dbname") or self.db_name)
                        self._cached_creds = (user, password, dbname, None)
                        return user, password, dbname
                except json.JSONDecodeError:
                    pass
                self._cached_creds = ("dbuser", secret_str, self.db_name, None)
                return "dbuser", secret_str, self.db_name
            except Exception:
                continue

        caller = self._run_aws(["sts", "get-caller-identity", "--query", "Arn", "--output", "text"])
        sso_user = caller.rsplit("/", 1)[-1].lower()
        if not re.match(r"^[a-z0-9._+-]+@arrofinance\.com$", sso_user):
            raise RuntimeError(
                f"could not read RDS secret from Secrets Manager ({secret_ids}) and caller {caller} "
                "is not an @arrofinance.com SSO identity"
            )
        token = self._run_aws(
            [
                "rds",
                "generate-db-auth-token",
                "--hostname",
                rds_host,
                "--port",
                "5432",
                "--username",
                sso_user,
            ]
        )
        self._cached_creds = (sso_user, token, self.db_name, now + IAM_TOKEN_TTL_SECONDS)
        return sso_user, token, self.db_name

    def _is_tunnel_healthy(self) -> bool:
        return (
            self._proc is not None
            and self._proc.poll() is None
            and self._local_port is not None
            and _is_port_open("127.0.0.1", self._local_port)
        )

    def _start_tunnel_sync(self) -> str:
        if not self._is_tunnel_healthy():
            self.close()
            bastion = self._resolve_bastion_id()
            rds_host = self._resolve_rds_endpoint()
            port_env = os.environ.get("LOCAL_PORT")
            port = int(port_env) if port_env else _pick_free_port()

            log_fd, log_path = tempfile.mkstemp(prefix="postgres-mcp-ssm-", suffix=".log")
            self._log_path = log_path

            if self.ssm_document in ("galileo-replica-tunnel", "galileo-writer-tunnel"):
                params = json.dumps({"localPortNumber": [str(port)]})
            else:
                params = json.dumps(
                    {
                        "host": [rds_host],
                        "portNumber": ["5432"],
                        "localPortNumber": [str(port)],
                    }
                )

            with os.fdopen(log_fd, "wb") as log_file:
                self._proc = subprocess.Popen(
                    self._aws_cmd(
                        [
                            "ssm",
                            "start-session",
                            "--target",
                            bastion,
                            "--document-name",
                            self.ssm_document,
                            "--parameters",
                            params,
                        ]
                    ),
                    stdin=subprocess.DEVNULL,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )

            self._local_port = port
            self._rds_host = rds_host

            ready = False
            deadline = time.monotonic() + 30.0
            while time.monotonic() < deadline:
                if _is_port_open("127.0.0.1", port):
                    ready = True
                    break
                if self._proc.poll() is not None:
                    break
                time.sleep(0.25)

            if not ready:
                log_output = ""
                if self._log_path and os.path.exists(self._log_path):
                    try:
                        with open(self._log_path, encoding="utf-8", errors="replace") as f:
                            log_output = f.read().strip()
                    except OSError:
                        pass
                self.close()
                raise RuntimeError(
                    f"SSM tunnel to {rds_host} via {bastion} failed to open within 30s: {log_output}"
                )

        assert self._rds_host is not None
        assert self._local_port is not None
        user, password, dbname = self._resolve_credentials(self._rds_host)
        return (
            f"postgresql://{quote(user, safe='')}:{quote(password, safe='')}"
            f"@127.0.0.1:{self._local_port}/{quote(dbname, safe='')}"
            "?sslmode=require&connect_timeout=15"
        )

    async def get_database_url(self) -> str:
        if self._explicit_url:
            return self._explicit_url
        async with self._lock:
            return await asyncio.to_thread(self._start_tunnel_sync)

    def close(self) -> None:
        session_id: str | None = None
        if self._log_path and os.path.exists(self._log_path):
            try:
                with open(self._log_path, encoding="utf-8", errors="replace") as f:
                    for line in f:
                        match = re.search(r"Starting session with SessionId:\s*(\S+)", line)
                        if match:
                            session_id = match.group(1)
                            break
            except OSError:
                pass

        if session_id:
            try:
                subprocess.run(
                    self._aws_cmd(["ssm", "terminate-session", "--session-id", session_id]),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=5.0,
                    check=False,
                )
            except Exception:
                pass

        if self._proc is not None:
            try:
                os.killpg(self._proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            except Exception:
                try:
                    self._proc.terminate()
                except Exception:
                    pass
            try:
                self._proc.wait(timeout=2.0)
            except Exception:
                try:
                    os.killpg(self._proc.pid, signal.SIGKILL)
                except Exception:
                    pass
            self._proc = None

        if self._log_path:
            try:
                os.unlink(self._log_path)
            except OSError:
                pass
            self._log_path = None

        self._local_port = None


def build_resource_base_url(database_url: str) -> str:
    parts = urlsplit(database_url)
    if not parts.scheme or not parts.hostname:
        raise ValueError("please provide a valid postgresql database URL")

    netloc = parts.hostname
    if parts.username:
        netloc = f"{parts.username}@{netloc}"
    if parts.port:
        netloc = f"{netloc}:{parts.port}"

    return urlunsplit(("postgres", netloc, "/", "", ""))


def build_resource_uri(resource_base_url: str, table_name: str) -> str:
    parts = urlsplit(resource_base_url)
    return urlunsplit((parts.scheme, parts.netloc, f"/{table_name}/{SCHEMA_PATH}", "", ""))


async def fetch_rows(database_url: str, sql: str, params: tuple[object, ...] = ()) -> list[dict[str, object]]:
    connection = await psycopg.AsyncConnection.connect(database_url)
    try:
        async with connection.cursor(row_factory=dict_row) as cursor:
            await cursor.execute("begin transaction read only")
            try:
                await cursor.execute(sql, params)
                return await cursor.fetchall()
            finally:
                await connection.rollback()
    finally:
        await connection.close()


async def run_read_only_query(database_url: str, sql: str) -> list[dict[str, object]]:
    connection = await psycopg.AsyncConnection.connect(database_url)
    try:
        async with connection.cursor(row_factory=dict_row) as cursor:
            await cursor.execute("begin transaction read only")
            try:
                await cursor.execute(sql)
                if cursor.description is None:
                    return []
                return await cursor.fetchall()
            finally:
                await connection.rollback()
    finally:
        await connection.close()


def create_server(get_database_url: Callable[[], Awaitable[str]]) -> Server:
    server = Server(name=SERVER_NAME, version=SERVER_VERSION)

    @server.list_resources()
    async def list_resources() -> list[types.Resource]:
        database_url = await get_database_url()
        resource_base_url = build_resource_base_url(database_url)
        rows = await fetch_rows(
            database_url,
            """
            select table_name
            from information_schema.tables
            where table_schema = 'public'
            order by table_name
            """,
        )
        return [
            types.Resource(
                uri=build_resource_uri(resource_base_url, row["table_name"]),
                mimeType="application/json",
                name=f'"{row["table_name"]}" database schema',
            )
            for row in rows
        ]

    @server.read_resource()
    async def read_resource(uri: types.AnyUrl) -> list[ReadResourceContents]:
        path_parts = [part for part in urlsplit(str(uri)).path.split("/") if part]
        if len(path_parts) != 2 or path_parts[1] != SCHEMA_PATH:
            raise ValueError("invalid resource URI")

        table_name = path_parts[0]
        database_url = await get_database_url()
        rows = await fetch_rows(
            database_url,
            """
            select column_name, data_type
            from information_schema.columns
            where table_schema = 'public'
              and table_name = %s
            order by ordinal_position
            """,
            (table_name,),
        )
        return [
            ReadResourceContents(
                content=json.dumps(rows, indent=2, default=str),
                mime_type="application/json",
            )
        ]

    @server.list_tools()
    async def list_tools() -> list[types.Tool]:
        return [
            types.Tool(
                name="query",
                description=(
                    "Run a read-only PostgreSQL query. Supports SELECT-style reads and "
                    "EXPLAIN statements, including EXPLAIN ANALYZE when the explained "
                    "statement is valid in a read-only transaction."
                ),
                inputSchema={
                    "type": "object",
                    "properties": {
                        "sql": {"type": "string"},
                    },
                    "required": ["sql"],
                },
            )
        ]

    @server.call_tool()
    async def call_tool(
        name: str,
        arguments: dict[str, object] | None,
    ) -> list[types.TextContent]:
        if name != "query":
            raise ValueError(f"unknown tool: {name}")

        sql = (arguments or {}).get("sql")
        if not isinstance(sql, str) or not sql.strip():
            raise ValueError("sql must be a non-empty string")

        database_url = await get_database_url()
        rows = await run_read_only_query(database_url, sql)
        return [types.TextContent(type="text", text=json.dumps(rows, indent=2, default=str))]

    return server


async def run_server(tunnel: SSMTunnelManager) -> None:
    server = create_server(tunnel.get_database_url)
    async with stdio_server() as (read_stream, write_stream):
        await server.run(
            read_stream,
            write_stream,
            InitializationOptions(
                server_name=SERVER_NAME,
                server_version=SERVER_VERSION,
                capabilities=server.get_capabilities(
                    notification_options=NotificationOptions(),
                    experimental_capabilities={},
                ),
            ),
        )


def main() -> int:
    args = sys.argv[1:]
    explicit_url = args[0] if args else os.environ.get("POSTGRES_URL")
    tunnel = SSMTunnelManager(explicit_url=explicit_url)
    atexit.register(tunnel.close)

    def _handle_signal(signum: int, _frame: object) -> None:
        tunnel.close()
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    try:
        asyncio.run(run_server(tunnel))
    finally:
        tunnel.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
