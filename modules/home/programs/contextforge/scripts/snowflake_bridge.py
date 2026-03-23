#!/usr/bin/env python3
import argparse
import asyncio
import json
import logging
from collections.abc import Iterable

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, PlainTextResponse
import uvicorn


logger = logging.getLogger("contextforge.snowflake_bridge")


class StdioJsonRpcBridge:
    def __init__(self, cmd: str, response_timeout: float):
        self.cmd = cmd
        self.response_timeout = response_timeout
        self.proc = None
        self.pending = {}
        self.pending_lock = asyncio.Lock()
        self.stdout_task = None
        self.stderr_task = None

    async def start(self) -> None:
        if self.proc and self.proc.returncode is None:
            return

        logger.info("starting snowflake stdio bridge subprocess")
        self.proc = await asyncio.create_subprocess_shell(
            self.cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        self.stdout_task = asyncio.create_task(self._pump_stdout())
        self.stderr_task = asyncio.create_task(self._pump_stderr())

    async def stop(self) -> None:
        if not self.proc:
            return

        if self.proc.returncode is None:
            self.proc.terminate()
            try:
                await asyncio.wait_for(self.proc.wait(), timeout=2)
            except asyncio.TimeoutError:
                self.proc.kill()
                await self.proc.wait()

        await self._fail_pending("snowflake bridge subprocess stopped")

    async def _pump_stdout(self) -> None:
        assert self.proc is not None
        assert self.proc.stdout is not None

        try:
            while True:
                line = await self.proc.stdout.readline()
                if not line:
                    break

                text = line.decode(errors="replace").strip()
                if not text:
                    continue

                logger.debug("snowflake bridge stdout: %s", text)
                try:
                    parsed = json.loads(text)
                except json.JSONDecodeError:
                    continue

                for candidate in self._iter_candidates(parsed):
                    response_id = candidate.get("id")
                    if response_id is None:
                        continue

                    async with self.pending_lock:
                        future = self.pending.pop(self._id_key(response_id), None)

                    if future and not future.done():
                        future.set_result(candidate)
        except Exception:
            logger.exception("snowflake bridge stdout pump crashed")
        finally:
            await self._fail_pending("snowflake bridge subprocess closed stdout")

    async def _pump_stderr(self) -> None:
        assert self.proc is not None
        assert self.proc.stderr is not None

        try:
            while True:
                line = await self.proc.stderr.readline()
                if not line:
                    break
                text = line.decode(errors="replace").rstrip()
                if text:
                    logger.warning("snowflake bridge stderr: %s", text)
        except Exception:
            logger.exception("snowflake bridge stderr pump crashed")

    async def _fail_pending(self, message: str) -> None:
        async with self.pending_lock:
            pending = list(self.pending.values())
            self.pending.clear()

        for future in pending:
            if not future.done():
                future.set_exception(RuntimeError(message))

    @staticmethod
    def _iter_candidates(payload: object) -> Iterable[dict]:
        if isinstance(payload, dict):
            yield payload
            return

        if isinstance(payload, list):
            for item in payload:
                if isinstance(item, dict):
                    yield item

    @staticmethod
    def _id_key(value: object) -> str:
        return json.dumps(value, sort_keys=True, separators=(",", ":"))

    @staticmethod
    def _error_response(request_id: object, code: int, message: str) -> dict:
        return {
            "jsonrpc": "2.0",
            "id": request_id,
            "error": {
                "code": code,
                "message": message,
            },
        }

    async def request(self, payload: dict, raw_body: str) -> dict:
        request_id = payload.get("id")
        if request_id is None:
            raise ValueError("request payload is missing id")

        await self.start()
        if not self.proc or self.proc.returncode is not None or not self.proc.stdin:
            return self._error_response(
                request_id,
                -32002,
                "snowflake bridge subprocess is not running",
            )

        future = asyncio.get_running_loop().create_future()
        id_key = self._id_key(request_id)

        async with self.pending_lock:
            self.pending[id_key] = future

        try:
            self.proc.stdin.write((raw_body.rstrip() + "\n").encode())
            await self.proc.stdin.drain()
        except Exception as exc:
            async with self.pending_lock:
                self.pending.pop(id_key, None)
            return self._error_response(
                request_id,
                -32003,
                f"snowflake bridge failed to write request: {exc}",
            )

        try:
            return await asyncio.wait_for(future, timeout=self.response_timeout)
        except asyncio.TimeoutError:
            async with self.pending_lock:
                self.pending.pop(id_key, None)
            return self._error_response(
                request_id,
                -32001,
                (
                    "snowflake bridge timed out waiting "
                    f"{self.response_timeout:g}s for an mcp response"
                ),
            )
        except Exception as exc:
            return self._error_response(
                request_id,
                -32004,
                str(exc),
            )

    async def notify(self, raw_body: str) -> None:
        await self.start()
        if not self.proc or self.proc.returncode is not None or not self.proc.stdin:
            raise RuntimeError("snowflake bridge subprocess is not running")

        self.proc.stdin.write((raw_body.rstrip() + "\n").encode())
        await self.proc.stdin.drain()


def build_app(bridge: StdioJsonRpcBridge) -> FastAPI:
    app = FastAPI()

    @app.post("/mcp")
    async def post_mcp(request: Request):
        body = await request.body()
        if not body:
            return PlainTextResponse("accepted", status_code=202)

        try:
            payload = json.loads(body)
        except json.JSONDecodeError as exc:
            return PlainTextResponse(f"invalid json payload: {exc}", status_code=400)

        if payload == {}:
            return PlainTextResponse("accepted", status_code=202)

        raw_body = body.decode(errors="replace")
        if isinstance(payload, dict) and "id" in payload:
            response = await bridge.request(payload, raw_body)
            return JSONResponse(response)

        try:
            await bridge.notify(raw_body)
        except Exception as exc:
            logger.warning("snowflake bridge notify failed: %s", exc)
            return PlainTextResponse(str(exc), status_code=503)

        return PlainTextResponse("accepted", status_code=202)

    @app.get("/healthz")
    async def healthz():
        return PlainTextResponse("ok")

    return app


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Snowflake-specific MCP stdio bridge with deterministic request timeouts."
    )
    parser.add_argument("--cmd", required=True, help="stdio command to run")
    parser.add_argument("--port", type=int, required=True, help="port to bind")
    parser.add_argument("--host", default="127.0.0.1", help="host to bind")
    parser.add_argument(
        "--response-timeout",
        type=float,
        default=15.0,
        help="seconds to wait for a matching JSON-RPC response",
    )
    parser.add_argument(
        "--log-level",
        default="info",
        choices=["debug", "info", "warning", "error", "critical"],
        help="uvicorn log level",
    )
    return parser.parse_args()


async def serve(args: argparse.Namespace) -> None:
    bridge = StdioJsonRpcBridge(args.cmd, args.response_timeout)
    await bridge.start()

    config = uvicorn.Config(
        build_app(bridge),
        host=args.host,
        port=args.port,
        log_level=args.log_level,
        lifespan="off",
    )
    server = uvicorn.Server(config)

    try:
        await server.serve()
    finally:
        await bridge.stop()


def main() -> None:
    args = parse_args()
    logging.basicConfig(
        level=getattr(logging, args.log_level.upper()),
        format="%(levelname)s:%(name)s:%(message)s",
    )
    try:
        asyncio.run(serve(args))
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
