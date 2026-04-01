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
            home-manager.useGlobalPkgs = true;
            home-manager.users.${primaryUser.username} = {
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
            home-manager.useGlobalPkgs = true;
            home-manager.users.${primaryUser.username} = {
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

        macbook-arm = darwinSystem {
          system = "aarch64-darwin";
          modules = nixDarwinCommonModules ++ [
            ./system/darwin/host-mac.nix
            { users.primaryUser = primaryUserInfo; }
          ];
        };
      };

      homeConfigurations = {
        debianWsl = home-manager.lib.homeManagerConfiguration {
          pkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
            inherit (nixpkgsConfig) config overlays;
          };
          modules =
            attrValues self.homeManagerModules
            ++ singleton (
              { config, pkgs, ... }:
              {
                home.username = config.home.user-info.username;
                home.homeDirectory = "/home/${config.home.username}";
                home.stateVersion = homeManagerStateVersion;
                home.user-info = primaryUserInfo;
                ext.wsl.enable = true;
                ext.wsl.usbipd.enable = true;
                # auto-detect smart card reader and distro
                # ext.wsl.usbipd.busid = "1-1";
                # ext.wsl.usbipd.distro_name = "Debian";
                ext.wsl.usbipd.auto_attach = true;
                ext.wsl.pcscd.enable = true;
                home.sessionVariables.LD_LIBRARY_PATH = "/usr/lib/wsl/lib:$LD_LIBRARY_PATH";

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
        home-wsl = import ./home/wsl.nix;
        home-git = import ./home/git.nix;
        home-git-ignores = import ./home/git-ignores.nix;
        home-gpg = import ./home/gpg.nix;
        home-gemini = import ./modules/home/programs/gemini;
        home-claude = import ./modules/home/programs/claude;
        home-contextforge = import ./modules/home/programs/contextforge;
        home-packages = import ./home/packages.nix;
        home-shells = import ./home/shells.nix;
        home-terminal = import ./home/terminal.nix;
        home-awscli = import ./modules/home/programs/awscli;
        home-codex = import ./modules/home/programs/codex;
        home-karabiner = import ./modules/home/programs/karabiner;
        home-podman = import ./modules/home/programs/podman;
        home-node = import ./modules/home/programs/node;
        home-nvim = import ./home/nvim.nix;
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
      formatter = forAllSystems (system: (import inputs.nixpkgs { inherit system; }).nixfmt-rfc-style);

      packages = forAllSystems (
        system:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            inherit (nixpkgsConfig) config overlays;
          };
        in
        {
          inherit (pkgs) gemini codex;
        }
      );
    };
}
