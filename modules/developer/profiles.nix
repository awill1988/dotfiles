{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  mcp_server_type = types.submodule {
    options = {
      command = mkOption {
        type = types.str;
        description = "Command to run the MCP server";
      };
      args = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Arguments for the MCP server command";
      };
      env = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = "Environment variables for the MCP server";
      };
      disabledTools = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "List of tool names to disable for this MCP server";
      };
    };
  };

  profile_options = {
    identity = {
      fullName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Full name for git/vcs commits";
      };
      email = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Primary email address for git/vcs commits";
      };
      github = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "GitHub handle";
      };
      signingKey = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "GPG/SSH signing key fingerprint or file path";
      };
      signingFormat = mkOption {
        type = types.nullOr (
          types.enum [
            "openpgp"
            "ssh"
          ]
        );
        default = null;
        description = "Commit signing format";
      };
    };

    aws = {
      profile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "AWS profile name";
      };
      region = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Default AWS region";
      };
      roleArn = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "AWS IAM Role ARN";
      };
    };

    git = {
      extraConfig = mkOption {
        type = types.attrs;
        default = { };
        description = "Custom gitconfig keys/sections";
      };
    };

    env = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Environment variables";
    };

    agents = {
      claude = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Claude configuration";
        };
        mcpServers = mkOption {
          type = types.attrsOf mcp_server_type;
          default = { };
          description = "Profile-specific MCP servers";
        };
        excludeMcpServers = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Global MCP servers to exclude";
        };
        effortLevel = mkOption {
          type = types.str;
          default = "medium";
          description = "Claude effort level";
        };
      };
      gemini = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Gemini configuration";
        };
        settings = mkOption {
          type = types.attrs;
          default = { };
          description = "Gemini settings";
        };
      };
      codex = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable Codex configuration";
        };
        config = mkOption {
          type = types.attrs;
          default = { };
          description = "Codex settings";
        };
      };
      agy = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = "Enable AGY configuration";
        };
        settings = mkOption {
          type = types.attrs;
          default = { };
          description = "AGY orchestrator settings";
        };
      };
    };
  };

  profile_submodule = types.submodule (
    { name, ... }:
    {
      options = profile_options // {
        name = mkOption {
          type = types.str;
          default = name;
          description = "Profile identifier";
        };
        inherits = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Parent profile name to extend (defaults to baseline)";
        };
        isPrimary = mkOption {
          type = types.bool;
          default = false;
          description = "Whether this profile is default fallback";
        };
        pathPrefixes = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Directory path prefixes that trigger this profile";
        };
      };
    }
  );

  host_submodule = types.submodule (
    { name, ... }:
    {
      options = {
        hostName = mkOption {
          type = types.str;
          default = name;
        };
        username = mkOption {
          type = types.str;
          description = "OS username on this machine (e.g. adam or adam.williams)";
        };
        system = mkOption {
          type = types.str;
          description = "Nix system string (e.g. aarch64-darwin or x86_64-linux)";
        };
        homeDirectory = mkOption {
          type = types.str;
          description = "Home directory path";
        };
        primaryProfile = mkOption {
          type = types.str;
          default = "personal";
          description = "Default fallback profile for this machine";
        };
        profileOverrides = mkOption {
          type = types.attrsOf (
            types.submodule (
              { ... }:
              {
                options = profile_options;
              }
            )
          );
          default = { };
          description = "Machine-level profile overrides";
        };
      };
    }
  );

  folder_override_submodule = types.submodule (
    { name, ... }:
    {
      options = profile_options // {
        path = mkOption {
          type = types.str;
          default = name;
          description = "Directory path for this folder override";
        };
        inherits = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "Parent profile name to extend";
        };
      };
    }
  );
in
{
  options.developer = {
    hostName = mkOption {
      type = types.str;
      default = "macbook-arm";
      description = "Active machine host identifier.";
    };

    baseline = mkOption {
      type = types.submodule (
        { ... }:
        {
          options = profile_options;
        }
      );
      default = { };
      description = "Global baseline defaults inherited by all profiles.";
    };

    hosts = mkOption {
      type = types.attrsOf host_submodule;
      default = { };
      description = "Machine definitions matrix.";
    };

    profiles = mkOption {
      type = types.attrsOf profile_submodule;
      default = { };
      description = "Developer profiles matrix.";
    };

    folderOverrides = mkOption {
      type = types.attrsOf folder_override_submodule;
      default = { };
      description = "Per-folder overrides extending profiles or baseline.";
    };
  };
}
