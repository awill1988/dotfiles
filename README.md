# dotfiles

This repository maintains my software development environment as code.

## WSL (Debian)

```bash
nix build \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  .#homeConfigurations.debianWsl.activationPackage && \
  ./result/activate
```

## macOS

```bash
nix build \
  --extra-experimental-features nix-command \
  --extra-experimental-features flakes \
  .#darwinConfigurations.bootstrap-arm.system && \
  ./result/sw/bin/darwin-rebuild switch --flake .#macbook-arm
```
