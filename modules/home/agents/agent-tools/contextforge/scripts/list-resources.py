import json
from pathlib import Path
import sys
from urllib.parse import urlencode
from urllib.request import Request, urlopen


def list_resources(base_url, collection, token, open_url=urlopen):
    """Read every cursor page before replacing a virtual server's associations."""
    items = []
    cursor = None
    seen = set()
    while True:
        query = {"include_pagination": "true", "limit": 100}
        if cursor:
            query["cursor"] = cursor
        request = Request(
            f"{base_url}/v1/{collection}?{urlencode(query)}",
            headers={"Authorization": f"Bearer {token}"},
        )
        with open_url(request, timeout=15) as response:
            page = json.load(response)
        items.extend(page[collection])
        cursor = page.get("nextCursor")
        if not cursor:
            return items
        if cursor in seen:
            raise RuntimeError("gateway returned a repeated pagination cursor")
        seen.add(cursor)


if __name__ == "__main__":
    base_url, collection, token_path = sys.argv[1:]
    print(json.dumps(list_resources(base_url, collection, Path(token_path).read_text().strip())))
