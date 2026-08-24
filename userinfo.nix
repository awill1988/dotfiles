{ lib }:
{
  # Layer 1: Global Baseline Defaults
  baseline = {
    identity = {
      fullName = "Adam Williams";
      github = "awill1988";
      signingKey = "4A0DB07DEDB705FBA45F557B7A0F7A351FABE619";
      signingFormat = "ssh";
      email = "adam@williams.engineer";
    };
    aws = {
      region = "us-east-1";
      profile = "personal";
    };
  };

  # Layer 3: Machine / Host Definitions
  hosts = {
    "macbook-personal" = {
      username = "adam";
      system = "aarch64-darwin";
      homeDirectory = "/Users/adam";
      primaryProfile = "personal";
    };

    "wsl-debian-personal" = {
      username = "adam";
      system = "x86_64-linux";
      homeDirectory = "/home/adam";
      primaryProfile = "personal";
    };
  };

  # Layer 2: Developer Profiles Matrix
  profiles = {
    personal = {
      isPrimary = true;
      pathPrefixes = [
        "~/projects/personal"
        "~/projects/awill1988"
      ];
    };

    work = {
      identity.email = "adam@arrofinance.com";
      pathPrefixes = [ "~/projects/arro" ];
      aws = {
        profile = "arro-staging";
        region = "us-west-2";
      };
      agents.claude = {
        configDir = "~/.config/claude-secondary";
        excludeMcpServers = [ "blender" ];
        mcpServers = {
          atlassian = {
            command = "mcp-remote-wrapper";
            args = [
              "https://mcp.atlassian.com/v1/mcp"
              "43012"
            ];
          };
          linear = {
            command = "mcp-remote-wrapper";
            args = [
              "https://mcp.linear.app/mcp"
              "43013"
            ];
          };
          vanta = {
            command = "npx";
            args = [
              "-y"
              "@vantasdk/vanta-mcp-server"
            ];
            env = {
              VANTA_ENV_FILE = "\${VANTA_ENV_FILE}";
            };
          };
          figma = {
            command = "npx";
            args = [
              "-y"
              "figma-developer-mcp@latest"
              "--stdio"
            ];
            env = {
              FIGMA_API_KEY = "\${FIGMA_API_KEY}";
            };
          };
          google-docs = {
            command = "npx";
            args = [
              "-y"
              "google-docs-mcp"
            ];
            env = {
              GOOGLE_CLIENT_ID = "\${GOOGLE_CLIENT_ID}";
              GOOGLE_CLIENT_SECRET = "\${GOOGLE_CLIENT_SECRET}";
            };
          };
          posthog = {
            command = "mcp-remote-wrapper";
            args = [
              "https://mcp.posthog.com/mcp"
              "43014"
            ];
          };
          sentry = {
            command = "mcp-remote-wrapper";
            args = [
              "https://mcp.sentry.dev/mcp"
              "43015"
            ];
          };
          grafana = {
            command = "uvx";
            args = [ "mcp-grafana" ];
            env = {
              GRAFANA_URL = "https://grafana.monitoring.arrofinance.io";
              GRAFANA_SERVICE_ACCOUNT_TOKEN = "\${GRAFANA_SERVICE_ACCOUNT_TOKEN}";
            };
          };
        };
      };
    };

    yourmoodai = {
      identity.email = "founder@yourmood.ai";
      pathPrefixes = [
        "~/projects/yourmood-ai"
        "~/projects/yourmood"
      ];
      aws = {
        profile = "yourmood-prod";
        region = "us-east-1";
      };
    };
  };

  # Layer 4: Per-Folder Overrides
  folderOverrides = {
    "~/projects/arro/security-audit" = {
      inherits = "work";
      aws.profile = "arro-audit-role";
      env = {
        SECURITY_AUDIT_ACTIVE = "1";
      };
    };
  };
}
