{
  description = "Adam's dotfiles";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixpkgs-unstable";

    darwin = {
      url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";
    mac-app-util.url = "github:hraban/mac-app-util";

    # vendored agent skills (installed via the agent-skills module, not the
    # claude code plugin marketplace); pinned in flake.lock, bumped with
    # `nix flake update golang-skills`.
    golang-skills = {
      url = "github:cxuu/golang-skills";
      flake = false;
    };

    stylix = {
      url = "github:danth/stylix/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      darwin,
      home-manager,
      flake-utils,
      mac-app-util,
      ...
    }@inputs:
    let
      inherit (darwin.lib) darwinSystem;
      inherit (inputs.nixpkgs.lib)
        attrValues
        makeOverridable
        mkForce
        optionalAttrs
        singleton
        ;

      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = f: inputs.nixpkgs.lib.genAttrs systems (system: f system);

      nixpkgsConfig = {
        config = {
          allowUnfree = true;
        };
        overlays = attrValues self.overlays;
      };

      homeManagerStateVersion = "25.05";

      primaryUserInfo = import ./userinfo.nix { inherit (inputs.nixpkgs) lib; };

      nixDarwinCommonModules = attrValues self.darwinModules ++ [
        mac-app-util.darwinModules.default

        home-manager.darwinModules.home-manager
        (
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            inherit (config.users) primaryUser;
          in
          {
            nixpkgs = nixpkgsConfig;
            users.users.${primaryUser.username}.home = "/Users/${primaryUser.username}";
            # useGlobalPkgs intentionally NOT set: stylix wires nixpkgs.config
            # inside the home-manager scope, which collides with useGlobalPkgs
            # and emits a deprecation warning. instead, give home-manager its
            # own nixpkgs eval seeded with the same config + overlays as the
            # darwin one so cf2tf, pkgs-unstable, etc. remain visible to HM.
            home-manager.users.${primaryUser.username} = {
              nixpkgs = nixpkgsConfig;
              imports = attrValues self.homeManagerModules ++ [ mac-app-util.homeManagerModules.default ];
              home.stateVersion = homeManagerStateVersion;
              home.user-info = config.users.primaryUser;
            };
          }
        )
      ];

      nixosCommonModules = attrValues self.nixosModules ++ [
        home-manager.nixosModules.home-manager
        (
          {
            config,
            lib,
            pkgs,
            ...
          }:
          let
            inherit (config.users) primaryUser;
          in
          {
            nixpkgs = nixpkgsConfig;
            users.users.${primaryUser.username} = {
              home = "/home/${primaryUser.username}";
              isNormalUser = true;
              isSystemUser = false;
              initialPassword = "helloworld";
              extraGroups = [ "wheel" ];
              shell = pkgs.zsh;
            };
            home-manager.users.${primaryUser.username} = {
              nixpkgs = nixpkgsConfig;
              imports = attrValues self.homeManagerModules ++ [ mac-app-util.homeManagerModules.default ];
              home.stateVersion = homeManagerStateVersion;
              home.user-info = config.users.primaryUser;
            };
          }
        )
      ];
    in
    {
      darwinConfigurations = rec {
        bootstrap-arm = makeOverridable darwinSystem {
          system = "aarch64-darwin";
          modules = [
            self.darwinModules.common
            self.darwinModules.darwin-bootstrap
            { nixpkgs = nixpkgsConfig; }
          ];
        };

        macbook-personal = darwinSystem {
          system = "aarch64-darwin";
          modules = nixDarwinCommonModules ++ [
            ./system/darwin/host-mac.nix
            {
              users.primaryUser = {
                username = primaryUserInfo.hosts.macbook-personal.username;
                fullName = primaryUserInfo.baseline.identity.fullName;
              };
              developer = {
                hostName = "macbook-personal";
                baseline = primaryUserInfo.baseline;
                hosts = primaryUserInfo.hosts;
                profiles = primaryUserInfo.profiles;
                folderOverrides = primaryUserInfo.folderOverrides;
              };
              home-manager.sharedModules = [
                {
                  developer = {
                    hostName = "macbook-personal";
                    baseline = primaryUserInfo.baseline;
                    hosts = primaryUserInfo.hosts;
                    profiles = primaryUserInfo.profiles;
                    folderOverrides = primaryUserInfo.folderOverrides;
                  };
                }
              ];
            }
          ];
        };
      };

      homeConfigurations = {
        wsl-debian-personal = home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
            inherit (nixpkgsConfig) config overlays;
          };
          modules =
            attrValues self.homeManagerModules
            ++ singleton (
              { config, pkgs, ... }:
              {
                home.username = primaryUserInfo.hosts.wsl-debian-personal.username;
                home.homeDirectory = primaryUserInfo.hosts.wsl-debian-personal.homeDirectory;
                home.stateVersion = homeManagerStateVersion;
                home.user-info = {
                  username = primaryUserInfo.hosts.wsl-debian-personal.username;
                  fullName = primaryUserInfo.baseline.identity.fullName;
                };
                developer = {
                  hostName = "wsl-debian-personal";
                  baseline = primaryUserInfo.baseline;
                  hosts = primaryUserInfo.hosts;
                  profiles = primaryUserInfo.profiles;
                  folderOverrides = primaryUserInfo.folderOverrides;
                };
                ext.wsl.enable = true;
                ext.wsl.usbipd.enable = true;
                # auto-detect smart card reader and distro
                # ext.wsl.usbipd.busid = "1-1";
                # ext.wsl.usbipd.distro_name = "Debian";
                ext.wsl.usbipd.auto_attach = true;
                ext.wsl.pcscd.enable = true;
                home.sessionVariables = {
                  LD_LIBRARY_PATH = "/usr/lib/wsl/lib:${pkgs.onnxruntime}/lib:${pkgs.openssl.out}/lib:$LD_LIBRARY_PATH";
                  PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig:${pkgs.onnxruntime.dev}/lib/pkgconfig:$PKG_CONFIG_PATH";
                  ORT_STRATEGY = "system";
                  ORT_PREFER_DYNAMIC_LINK = "true";
                  ORT_LIB_PATH = "${pkgs.onnxruntime}/lib";
                  ORT_LIB_LOCATION = "${pkgs.onnxruntime}/lib";
                  PROTOC = "${pkgs.protobuf}/bin/protoc";
                };
                programs.contextforge.windows_dev.workspace_root = "${config.home.homeDirectory}/projects/yourmood.ai/workshop";

                # codex: skip tests on WSL to avoid flaky upstream suite
                programs.codex.package = pkgs.codex.overrideAttrs (old: {
                  doCheck = false;
                });
              }
            );
        };
      };

      defaultPackage.x86_64-linux = self.homeConfigurations.debianWsl.activationPackage;

      darwinModules = {
        common = import ./system/common.nix;
        packages = import ./system/packages.nix;

        darwin-bootstrap = import ./system/darwin/bootstrap.nix;
        darwin-packages = import ./system/darwin/packages.nix;
        darwin-system = import ./system/darwin/system.nix;
        darwin-homebrew = import ./system/darwin/homebrew.nix;

        users-primaryUser = import ./modules/users.nix;
      };

      homeManagerModules = {
        home-config-files = import ./home/config-files.nix;
        home-fonts = import ./home/fonts.nix;
        home-theme = import ./home/theme.nix;
        home-stylix = inputs.stylix.homeModules.stylix;
        home-wsl = import ./home/wsl.nix;

        # AI Agents & MCP Ecosystem
        home-agent-claude = import ./modules/home/agents/core/claude;
        home-agent-codex = import ./modules/home/agents/core/codex;
        home-agent-gemini = import ./modules/home/agents/core/gemini;
        home-agent-agy = import ./modules/home/agents/core/agy;
        home-agent-prompts = import ./modules/home/agents/orchestration/agent-prompts;
        home-agent-skills = import ./modules/home/agents/orchestration/agent-skills {
          golang_skills_src = inputs.golang-skills;
        };
        home-agent-tools = import ./modules/home/agents/agent-tools;
        home-agent-local-ai = import ./modules/home/agents/local-ai;

        # Editors
        home-editor-neovim = import ./modules/home/editor/neovim;
        home-editor-code = import ./modules/home/editor/code;

        # Security & Identity
        home-security-gpg = import ./modules/home/security/gpg;
        home-security-ssh = import ./modules/home/security/ssh;
        home-security-smartcard = import ./modules/home/security/smartcard;
        home-security-credentials = import ./modules/home/security/credentials;
        home-security-audit = import ./modules/home/security/audit;

        # Languages
        home-lang-rust = import ./modules/home/languages/rust;
        home-lang-go = import ./modules/home/languages/go;
        home-lang-python = import ./modules/home/languages/python;
        home-lang-node = import ./modules/home/languages/node;
        home-lang-elixir = import ./modules/home/languages/elixir;
        home-lang-ruby = import ./modules/home/languages/ruby;
        home-lang-java = import ./modules/home/languages/java;

        # Terminal, Cloud, VCS, Hardware
        home-terminal-tmux = import ./modules/home/terminal/tmux;
        home-terminal-shell = import ./modules/home/terminal/shell;
        home-terminal-navigation = import ./modules/home/terminal/navigation;
        home-cloud-aws = import ./modules/home/cloud/aws;
        home-cloud-infra = import ./modules/home/cloud/infra;
        home-cloud-containers = import ./modules/home/cloud/containers;
        home-vcs-git = import ./modules/home/vcs/git;
        home-hardware-karabiner = import ./modules/home/hardware/karabiner;

        # Developer Profile Engine
        home-developer-profiles = import ./modules/home/developer/profiles.nix;

        home-user-info =
          { lib, ... }:
          {
            options.home.user-info =
              (self.darwinModules.users-primaryUser {
                inherit lib;
              }).options.users.primaryUser;
          };
      };

      overlays = (import ./overlays) // {
        rust-overlay = inputs.rust-overlay.overlays.default;
        pkgs-unstable = _: prev: {
          pkgs-unstable = import inputs.nixpkgs-unstable {
            inherit (prev.stdenv.hostPlatform) system;
            inherit (nixpkgsConfig) config;
          };
        };
        contextforge-gateway = import ./overlays/contextforge-gateway.nix {
          inherit (inputs) uv2nix pyproject-nix pyproject-build-systems;
        };
      };
      formatter = forAllSystems (
        system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
        in
        pkgs.writeShellScriptBin "nixfmt" ''
          if [ $# -eq 0 ]; then
            exec ${pkgs.nixfmt-rfc-style}/bin/nixfmt $(${pkgs.git}/bin/git ls-files '*.nix')
          else
            exec ${pkgs.nixfmt-rfc-style}/bin/nixfmt "$@"
          fi
        ''
      );

      packages = forAllSystems (
        system:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            inherit (nixpkgsConfig) config overlays;
          };
        in
        {
          inherit (pkgs) gemini codex agy;
        }
      );
    };
}
