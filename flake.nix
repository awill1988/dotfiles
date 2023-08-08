{
  description = "Adam Williams' dotfiles";

  inputs = {
    nixpkgs-stable.url = "github:NixOS/nixpkgs/23.05";

    darwin.url = "github:LnL7/nix-darwin/release-23.05";
    darwin.inputs.nixpkgs.follows = "nixpkgs-stable";

    home-manager.url = "github:nix-community/home-manager/release-23.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-stable";

    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, darwin, home-manager, flake-utils, ... }@inputs:
    let
      inherit (darwin.lib) darwinSystem;
      inherit (inputs.nixpkgs-stable.lib)
        attrValues makeOverridable optionalAttrs singleton;

      systems = [ "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      nixpkgsConfig = with inputs; rec {
        config = { allowUnfree = true; };
        overlays = attrValues self.overlays;
      };

      homeManagerStateVersion = "23.05";
      nixosStateVersion = "23.05";

      primaryUserInfo = {
        username = "adam.williams";
        email = "adam.williams@onxmaps.com";
        fullName = "Adam Williams";
        github = "awill1988";
      };

      nixDarwinCommonModules = attrValues self.darwinModules ++ [
        home-manager.darwinModules.home-manager
        ({ config, lib, pkgs, ... }:
          let inherit (config.users) primaryUser;
          in rec {
            nixpkgs = nixpkgsConfig;
            users.users.${primaryUser.username} = {
              home = "/Users/${primaryUser.username}";
              shell = pkgs.zsh;
            };
            home-manager.useGlobalPkgs = true;
            home-manager.users.${primaryUser.username} = {
              imports = attrValues self.homeManagerModules;
              home.stateVersion = homeManagerStateVersion;
              home.user-info = config.users.primaryUser;
            };
          })
      ];
    in {
      darwinConfigurations = rec {

        # Minimal configuration to bootstrap systems
        bootstrap-x86 = makeOverridable darwinSystem {
          system = "x86_64-darwin";
          modules = [
            self.darwinModules.common
            self.darwinModules.darwin-bootstrap
            { nixpkgs = nixpkgsConfig; }
          ];
        };

        bootstrap-arm = bootstrap-x86.override { system = "aarch64-darwin"; };

        # My macOS configuration
        macbook-x86 = darwinSystem {
          system = "x86_64-darwin";
          modules = nixDarwinCommonModules ++ [
            ./system/darwin/host-mac.nix
            { users.primaryUser = primaryUserInfo; }
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

      darwinModules = {
        common = import ./system/common.nix;
        packages = import ./system/packages.nix;

        darwin-bootstrap = import ./system/darwin/bootstrap.nix;
        darwin-packages = import ./system/darwin/packages.nix;
        darwin-system = import ./system/darwin/system.nix;

        users-primaryUser = import ./modules/users.nix;
      };

      homeManagerModules = {
        home-config-files = import ./home/config-files.nix;
        home-git = import ./home/git.nix;
        home-git-ignores = import ./home/git-ignores.nix;
        home-packages = import ./home/packages.nix;
        home-shells = import ./home/shells.nix;
        home-terminal = import ./home/terminal.nix;
        home-user-info = { lib, ... }: {
          options.home.user-info = (self.darwinModules.users-primaryUser {
            inherit lib;
          }).options.users.primaryUser;
        };
      };

      overlays = {
        pkgs-master = _: prev: {
          pkgs-master = import inputs.nixpkgs-master {
            inherit (prev.stdenv) system;
            inherit (nixpkgsConfig) config;
          };
        };
        pkgs-stable = _: prev: {
          pkgs-stable = import inputs.nixpkgs-stable {
            inherit (prev.stdenv) system;
            inherit (nixpkgsConfig) config;
          };
        };
        pkgs-unstable = _: prev: {
          pkgs-unstable = import inputs.nixpkgs-unstable {
            inherit (prev.stdenv) system;
            inherit (nixpkgsConfig) config;
          };
        };

        # Overlay useful on Macs with Apple Silicon
        apple-silicon = _: prev:
          optionalAttrs (prev.stdenv.system == "aarch64-darwin") {
            # Add access to x86 packages system is running Apple Silicon
            pkgs-x86 = import inputs.nixpkgs-unstable {
              system = "x86_64-darwin";
              inherit (nixpkgsConfig) config;
            };
          };

        extra = import ./overlays/extra.nix;
      };

      devShell = forAllSystems (system:
        let pkgs = nixpkgs.legacyPackages.${system};
        in pkgs.mkShell {
          nativeBuildInputs = with pkgs; [ rnix-lsp nixpkgs-fmt ];
        });
      formatter =
        forAllSystems (system: nixpkgs.legacyPackages.${system}.nixpkgs-fmt);
    };
}
