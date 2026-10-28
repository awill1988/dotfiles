import os
from pathlib import Path
import secrets
import sys
import tempfile


def initialize(path: Path) -> None:
    """Create persistent local credentials without overwriting an existing identity."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        return
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            for name in (
                "JWT_SECRET_KEY",
                "AUTH_ENCRYPTION_SECRET",
                "BASIC_AUTH_PASSWORD",
                "PLATFORM_ADMIN_PASSWORD",
                "DEFAULT_USER_PASSWORD",
            ):
                stream.write(f"{name}={secrets.token_urlsafe(48)}\n")
        try:
            os.link(temporary, path)
        except FileExistsError:
            pass
    finally:
        os.unlink(temporary)


if __name__ == "__main__":
    initialize(Path(sys.argv[1]))
