import jwt
import os
import time
import uuid

print(
    jwt.encode(
        {
            "sub": "admin@example.com",
            "iss": "mcpgateway",
            "aud": "mcpgateway-api",
            "iat": int(time.time()),
            "jti": str(uuid.uuid4()),
            "teams": None,
            "user": {
                "email": "admin@example.com",
                "full_name": "Local Admin",
                "is_admin": True,
                "auth_provider": "local",
            },
        },
        os.environ["JWT_SECRET_KEY"],
        algorithm="HS256",
    )
)
