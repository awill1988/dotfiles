# dotfiles

Personal dotfiles managed with [Nix](https://nixos.org/), supporting macOS (via nix-darwin) and WSL/Debian (via home-manager).

## Building and Activating

### macOS (first-time setup)

```bash
# build bootstrap configuration
nix --extra-experimental-features 'nix-command flakes' build .#darwinConfigurations.bootstrap-arm.system

# activate
sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-arm
```

### WSL/Debian

```bash
nix --extra-experimental-features 'nix-command flakes' build .#homeConfigurations.debianWsl.activationPackage && ./result/activate
```
