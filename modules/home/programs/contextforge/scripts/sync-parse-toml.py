import json
import os
import re
import sys

try:
    import tomllib
except ModuleNotFoundError:
    print("error: python3 lacks tomllib", file=sys.stderr)
    sys.exit(1)

config_path = sys.argv[1]
output_path = sys.argv[2]


def read_toml(path):
    try:
        with open(path, "rb") as handle:
            return tomllib.load(handle)
    except FileNotFoundError:
        return {}
    except tomllib.TOMLDecodeError as exc:
        print(f"error: invalid toml: {exc}", file=sys.stderr)
        sys.exit(1)


pattern = re.compile(r"\$(\w+)|\${([^}]+)}")


def current_platforms():
    platforms = {"linux" if sys.platform.startswith("linux") else sys.platform}
    if sys.platform.startswith("linux"):
        try:
            with open("/proc/version", encoding="utf-8") as version_file:
                if "microsoft" in version_file.read().lower():
                    platforms.add("wsl")
        except OSError:
            pass
    return platforms


available_platforms = current_platforms()


def expand_value(value, missing):
    if isinstance(value, str):
        for match in pattern.findall(value):
            env_name = match[0] or match[1]
            if os.environ.get(env_name) is None:
                missing.add(env_name)
        return os.path.expandvars(value)
    if isinstance(value, dict):
        return {key: expand_value(val, missing) for key, val in value.items()}
    if isinstance(value, list):
        return [expand_value(val, missing) for val in value]
    return value


def expand_headers(headers, missing):
    if not isinstance(headers, dict):
        return {}, missing
    resolved = {}
    for key, value in headers.items():
        resolved[key] = expand_value(value, missing)
    return resolved, missing


data = read_toml(config_path)
servers = data.get("servers", [])
if not isinstance(servers, list):
    servers = []

inventory = []
for item in servers:
    if not isinstance(item, dict):
        continue
    platforms = item.get("platforms") or []
    if platforms and not available_platforms.intersection(platforms):
        continue
    name = item.get("name")
    if not name:
        continue
    transport = (item.get("transport") or "http").lower()
    url = item.get("url")
    missing = set()
    headers, _ = expand_headers(item.get("headers", {}), missing)
    auth_headers = []
    auth_headers_raw = item.get("auth_headers")
    if isinstance(auth_headers_raw, list):
        for entry in auth_headers_raw:
            if not isinstance(entry, dict):
                continue
            key = entry.get("key")
            if key is None:
                continue
            value = expand_value(entry.get("value", ""), missing)
            auth_headers.append(
                {
                    "key": str(key),
                    "value": "" if value is None else str(value),
                }
            )
    elif headers:
        for key in sorted(headers.keys()):
            value = headers[key]
            auth_headers.append(
                {
                    "key": str(key),
                    "value": "" if value is None else str(value),
                }
            )

    oauth_config = item.get("oauth_config") or {}
    if isinstance(oauth_config, dict):
        oauth_config = expand_value(oauth_config, missing)
    else:
        oauth_config = {}

    auth_type = item.get("auth_type")
    if not auth_type:
        if oauth_config:
            auth_type = "oauth"
        elif auth_headers:
            auth_type = "authheaders"
    command = item.get("command")
    args = item.get("args") or []
    env = item.get("env") or {}
    bridge = item.get("bridge") or {}
    bridge_port = bridge.get("port")
    bridge_url = bridge.get("url")
    if bridge_port and not bridge_url:
        bridge_url = f"http://127.0.0.1:{bridge_port}/mcp"
    gateway_register = item.get("gateway_register")
    if gateway_register is None:
        if transport == "http":
            gateway_register = True
        else:
            gateway_register = bool(bridge_url)

    gateway_transport = None
    if transport in ("http", "streamablehttp", "streamable_http"):
        gateway_transport = "STREAMABLEHTTP"
    elif transport == "sse":
        gateway_transport = "SSE"
    elif transport == "stdio" and bridge_url:
        # stdio servers can register via their http bridge
        gateway_transport = "STREAMABLEHTTP"

    inventory.append(
        {
            "name": name,
            "transport": transport,
            "gateway_transport": gateway_transport,
            "url": url,
            "headers": headers,
            "missing_headers": sorted(missing),
            "auth_type": auth_type,
            "auth_headers": auth_headers,
            "oauth_config": oauth_config,
            "command": command,
            "args": args,
            "env": env,
            "bridge_url": bridge_url,
            "gateway_register": bool(gateway_register),
        }
    )

inventory = sorted(inventory, key=lambda item: item["name"])
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(inventory, handle, indent=2, sort_keys=True)
