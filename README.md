# dotfiles

![screenshot](screenshot.gif)

## Overview

This repository contains my personal dotfiles for creating a consistent development environment across macOS and Linux systems. It uses [Nix](https://nixos.org/) to manage packages, configurations, and dependencies declaratively, with first-class support for macOS via nix-darwin and additional support for WSL/Debian environments.

## Who is this for?

This configuration is designed for developers who:

- Have a GitHub account and actively contribute to repositories
- Want to sign their commits with either SSH keys or GPG (including hardware tokens like YubiKey)
- Work across multiple machines (macOS, WSL, Linux) and want consistent tooling
- Prefer declarative system configuration over manual setup scripts
- Are comfortable with or want to learn Nix for reproducible development environments

If you're looking for a well-structured, production-ready dotfiles setup that emphasizes security (commit signing), portability (works anywhere), and reproducibility (Nix), you're in the right place.

## Getting Started

<div style="background-color: #ffebee; border-left: 4px solid #f44336; padding: 12px 16px; margin: 16px 0; border-radius: 4px;">
  <strong>⚠️ Important: Defaults Are Personal</strong>
  <p style="margin: 8px 0 0 0;">
    The default values in <code>userinfo.nix</code> are Adam's personal configuration. <strong>They will not work for you.</strong> You must customize these values before building, otherwise the configuration will use Adam's username, email, GitHub account, and GPG keys.
  </p>
</div>

### Quick Customization with sed

Fork this repository and use sed to customize `userinfo.nix` in one go:

```bash
# Clone your fork (replace 'yourgithub' with your GitHub username)
git clone https://github.com/yourgithub/dotfiles.git
cd dotfiles

# macOS (BSD sed - requires empty string after -i)
sed -i '' \
  -e 's/username = "adam"/username = "yourname"/' \
  -e 's/fullName = "Adam Williams"/fullName = "Your Full Name"/' \
  -e 's/github = "awill1988"/github = "yourgithub"/' \
  -e 's/email = "adam@williams.engineer"/email = "you@example.com"/' \
  -e 's/signingKey = "4A0DB07DEDB705FBA45F557B7A0F7A351FABE619"/signingKey = "YOUR-GPG-KEY-ID"/' \
  -e 's/signingFormat = "openpgp"/signingFormat = "openpgp"/' \
  userinfo.nix

# Linux/WSL (GNU sed)
# sed -i \
#   -e 's/username = "adam"/username = "yourname"/' \
#   -e 's/fullName = "Adam Williams"/fullName = "Your Full Name"/' \
#   -e 's/github = "awill1988"/github = "yourgithub"/' \
#   -e 's/email = "adam@williams.engineer"/email = "you@example.com"/' \
#   -e 's/signingKey = "4A0DB07DEDB705FBA45F557B7A0F7A351FABE619"/signingKey = "YOUR-GPG-KEY-ID"/' \
#   -e 's/signingFormat = "openpgp"/signingFormat = "openpgp"/' \
#   userinfo.nix

# To disable signing, use null instead:
# sed -i '' -e 's/signingKey = "4A0DB07DEDB705FBA45F557B7A0F7A351FABE619"/signingKey = null/' userinfo.nix  # macOS
# sed -i '' -e 's/signingFormat = "openpgp"/signingFormat = null/' userinfo.nix  # macOS

# Verify your changes
cat userinfo.nix

# Commit your customizations
git add userinfo.nix
git commit -m "chore: customize userinfo for my environment"
git push
```

### Manual Customization

Prefer to edit manually? Open `userinfo.nix` and replace these values:

- `username`: your system username (currently: `"adam"`)
- `fullName`: your full name for git commits (currently: `"Adam Williams"`)
- `git.github`: your github username (currently: `"awill1988"`)
- `git.signingKey`: your gpg key id OR ssh key path (currently: `"4A0DB07DEDB705FBA45F557B7A0F7A351FABE619"`)
- `git.signingFormat`: `"openpgp"` or `"ssh"` (currently: `"openpgp"`)
- `git.email`: your primary git email (currently: `"adam@williams.engineer"`)
- `git.emailSecondary`: optional secondary email for work/personal separation (currently: `null`)

### Test Drive (Optional)

Want to explore the structure before customizing? You can build with the defaults, but **this will not work on your system** since it references Adam's username, directories, and keys that don't exist on your machine:

```bash
# macOS
nix build .#darwinConfigurations.bootstrap-arm.system

# WSL/Debian
nix build .#homeConfigurations.debianWsl.activationPackage
```

The build may succeed but activation will fail. This is only useful for examining the Nix code structure—you must customize `userinfo.nix` before actually using this configuration.

<div style="background-color: #e8f5e9; border-left: 4px solid #4caf50; padding: 12px 16px; margin: 16px 0; border-radius: 4px;">
  <strong>💡 Commit Signing Behavior</strong>
  <p style="margin: 8px 0 0 0;">
    Commit signing is enabled only when both <code>git.signingKey</code> and <code>git.signingFormat</code> are set. To disable signing, set either value to <code>null</code>.
  </p>
  <p style="margin: 8px 0 0 0;">
    Examples:<br>
    • GPG signing: <code>signingKey = "4A0DB07D..."</code>, <code>signingFormat = "openpgp"</code><br>
    • SSH signing: <code>signingKey = "~/.ssh/id_ed25519.pub"</code>, <code>signingFormat = "ssh"</code><br>
    • No signing: <code>signingKey = null</code>, <code>signingFormat = null</code>
  </p>
</div>

## Building and Activating

### macOS

First-time setup requires bootstrapping the darwin configuration:

```bash
# Build the bootstrap configuration
nix build .#darwinConfigurations.bootstrap-arm.system

# Apply the full system configuration
sudo ./result/sw/bin/darwin-rebuild switch --flake .#macbook-arm
```

After the initial setup, rebuild with:

```bash
darwin-rebuild switch --flake .#macbook-arm
```

## WSL and Debian Support

This configuration also supports WSL (Windows Subsystem for Linux) and Debian environments through home-manager. While macOS is the primary platform, the home-manager modules provide a consistent shell, terminal, and development tool configuration across all platforms.

### Building for WSL/Debian

```bash
nix build .#homeConfigurations.debianWsl.activationPackage && ./result/activate
```

### What Works on WSL

The WSL configuration includes:
- Consistent shell environment (zsh with oh-my-zsh, starship prompt)
- Development tools and packages
- Git configuration with conditional includes
- GPG and SSH agent integration
- YubiKey support via usbipd (auto-attach capability)
- Neovim configuration
- All home-manager managed dotfiles

### What's Different

WSL-specific features:
- `ext.wsl.enable = true` - enables WSL-specific configurations
- `ext.wsl.usbipd.enable = true` - manages YubiKey/smart card access
- `ext.wsl.usbipd.auto_attach = true` - automatically attaches USB devices
- Custom `LD_LIBRARY_PATH` for WSL library compatibility

Note: System-level packages and configurations (like those in `system/darwin/`) are not available on WSL—only home-manager modules apply.
