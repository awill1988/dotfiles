import jwt
import warnings

warnings.filterwarnings("ignore")
print(
    jwt.encode(
        {
            "sub": "admin@example.com",
            "iss": "mcpgateway",
            "aud": "mcpgateway-api",
            "user": {
                "email": "admin@example.com",
                "full_name": "Local Admin",
                "is_admin": True,
                "auth_provider": "local",
            },
        },
        "my-test-key",
        algorithm="HS256",
    )
)
