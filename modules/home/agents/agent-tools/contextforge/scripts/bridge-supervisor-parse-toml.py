import sys

try:
    import tomllib
except ModuleNotFoundError:
    print("error: python3 lacks tomllib", file=sys.stderr)
    sys.exit(1)

config_path = sys.argv[1]
with open(config_path, "rb") as f:
    data = tomllib.load(f)


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

for server in data.get("servers", []):
    if not isinstance(server, dict):
        continue
    transport = (server.get("transport") or "").lower()
    if transport != "stdio":
        continue
    platforms = server.get("platforms") or []
    if platforms and not available_platforms.intersection(platforms):
        continue
    bridge = server.get("bridge") or {}
    port = bridge.get("port")
    if not port:
        continue
    name = server.get("name", "unknown")
    command = server.get("command", "")
    args = server.get("args") or []
    env = server.get("env") or {}
    cmd_parts = [command] + args
    env_pairs = " ".join(f"{k}={v}" for k, v in env.items())
    print(f"{name}\t{' '.join(cmd_parts)}\t{port}\t{env_pairs}")
