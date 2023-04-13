[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

# Adam's dotfiles and Nix config

> These are my dotfiles. There are many like them, but these are mine.
> -Martin

## Bootstrapping a new machine

On a new mac, you'll need to figure this out yourself.

But you need:

- Nix
- darwin-nix

### Flakes

With Nix installed, we're ready to bootstrap and install the actual
configuration.

Flakes is an upcoming feature of Nix and here's out it works with bootstrapping
MacOS environments much like Homebrew does!

## Quick & Dirty

```bash
pushd /tmp
nix build \
    --extra-experimental-features nix-command \
    --extra-experimental-features flakes \
    'git+ssh://git@github.com/awill1988/dotfiles.git#darwinConfigurations.bootstrap-arm.system' && \
./result/sw/bin/darwin-rebuild switch --flake 'git+ssh://git@github.com/awill1988/dotfiles.git#bootstrap-arm' && \
darwin-rebuild switch --flake 'git+ssh://git@github.com/awill1988/dotfiles.git#macbook-arm'
popd
```

---
Then open up a new terminal session and run:

```bash
darwin-rebuild switch --flake .#macbook-arm
```

## You're done

Open new Terminal and simply type `zsh` and return
