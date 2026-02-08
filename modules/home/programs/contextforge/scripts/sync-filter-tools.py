import fnmatch
import json
import sys

try:
    import tomllib
except ModuleNotFoundError:
    import tomli as tomllib

raw = sys.stdin.read()
if not raw.strip():
    print(json.dumps({"ids": [], "excluded": []}))
    sys.exit(0)

try:
    tools = json.loads(raw)
except (json.JSONDecodeError, ValueError):
    print(json.dumps({"ids": [], "excluded": []}))
    sys.exit(0)

with open(sys.argv[1], "rb") as f:
    config = tomllib.load(f)

patterns = config.get("exclude_tools", [])
included, excluded = [], []
for t in tools:
    name = t.get("name", "")
    if any(fnmatch.fnmatch(name, p) for p in patterns):
        excluded.append(name)
    else:
        included.append(t.get("id", ""))

result = {"ids": included, "excluded": sorted(excluded)}
print(json.dumps(result))
