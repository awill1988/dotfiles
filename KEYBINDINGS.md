# keybindings philosophy

## design principles

1. **minimal memorization** - only 6 leader groups to remember
2. **which-key driven** - press `<leader>` and wait, it shows you options
3. **vim defaults preserved** - keep standard vim bindings where sensible
4. **consistent patterns** - use `[`/`]` for all prev/next navigation
5. **easy to maintain** - all keybindings centralized in one file

## the 6 groups

- `<leader>f` - **find** (files, grep, buffers, recent, help)
- `<leader>g` - **git** (stage, reset, blame, diff, preview)
- `<leader>c` - **code** (lsp: definition, actions, rename, symbols)
- `<leader>t` - **toggle** (explorer, database ui, numbers, wrap, spell)
- `<leader>w` - **window** (split, close, equalize)
- `<leader>b` - **buffer** (delete, force delete)
- `<leader>p` - **project** (sessions: list, load, save, delete)

## navigation patterns

### bracket notation (prev/next)
- `[b` / `]b` - buffers
- `[d` / `]d` - diagnostics
- `[g` / `]g` - git hunks
- `[a` / `]a` - ale errors
- `[q` / `]q` - quickfix

### window navigation
- `<c-h>` / `<c-j>` / `<c-k>` / `<c-l>` - focus left/down/up/right

## usage

press `<leader>` and wait - which-key will show you all available options

## implementation

all keybindings are centralized in `home/config/nvim/lua/ext/keymaps.lua`
