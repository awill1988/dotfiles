#!/usr/bin/env python3

import asyncio
import json
import sys
from urllib.parse import urlsplit, urlunsplit

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
            await cursor.execute(sql, params)
            return await cursor.fetchall()
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


def create_server(database_url: str) -> Server:
    resource_base_url = build_resource_base_url(database_url)
    server = Server(name=SERVER_NAME, version=SERVER_VERSION)

    @server.list_resources()
    async def list_resources() -> list[types.Resource]:
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

        rows = await run_read_only_query(database_url, sql)
        return [types.TextContent(type="text", text=json.dumps(rows, indent=2, default=str))]

    return server


async def run_server(database_url: str) -> None:
    server = create_server(database_url)
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
    if not args:
        print("please provide a database URL as a command-line argument", file=sys.stderr)
        return 1

    asyncio.run(run_server(args[0]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
