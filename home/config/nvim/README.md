# vim/neovim configuration differences from kennypete's .vimrc

this document clarifies intentional differences between kennypete's .vimrc and our implementation.

## options added (not in kennypete's original)

### neovim only
- `termguicolors = true` - enables 24-bit color (neovim-specific)
- `signcolumn = "yes"` - always show sign column (for lsp/git signs)
- `relativenumber = true` - relative line numbers (personal preference)
- `shell` - explicit shell configuration with fallback
- `mousetime = 500` - double-click timing control

### both vim and neovim
- `smartcase = true` - case-sensitive if uppercase present (common workflow improvement)
- `wildoptions = { "pum", "fuzzy" }` - fuzzy command-line completion

### clipboard handling differences
- **neovim**: `clipboard = "unnamedplus"` - system clipboard integration (+ register)
- **vim**: `clipboard += autoselect` - visual selections auto-copy to selection register
- kennypete uses `clipboard = autoselect` (selection register only, no system clipboard)

## options removed or modified

### intentionally removed (workflow/compatibility reasons)
- `autochdir` - **commented out**: interferes with project-based workflows and lsp
- `mouse = "a"` instead of `"ar"` - "ar" (all+report) is vim9-specific, "a" works universally
- `browsedir = "buffer"` - **removed from neovim** (unsupported), kept in classic vim
- `encoding = "utf-8"` - **removed from neovim** (always utf-8, not settable), kept in classic vim
- `clipboard += autoselect` - **removed from neovim** (unsupported); using `clipboard = "unnamedplus"` instead

### implemented (wsl/environment-specific)
- `t_u7=` - **implemented in classic vim**: prevents replace mode in wsl terminals

### not implemented (advanced/specialized features)
- `cdhome` - cd to home when no file specified
- `cmdwinheight = 9` - command-line window height
- `cpoptions+=nq` - compatibility options (n: number column for wrapped lines, q: join with count)
- `delcombine` - delete combining characters separately
- `foldclose = all` - auto-close folds when cursor leaves
- `foldcolumn = 1` - show fold column
- `foldlevelstart = 0` - start with all folds closed
- `helpheight = 13` - help window height
- `keywordprg = :help` - K command behavior (neovim defaults to lsp hover)
- `nolangremap` - language mapping behavior
- `maxcombine = 6` - max combining characters
- `nomousefocus` / `nomousehide` - mouse behavior details
- `numberwidth = 3` - line number width (we auto-calculate in neovim via `set_number_width()`)
- `printfont`, `printheader`, `printoptions` - printing settings (rarely used)
- `pumwidth = 18` - popup menu width
- `sessionoptions` - session save options (using persisted.nvim plugin instead)
- `shortmess = inxtToOs` - message abbreviations
- `showcmd` / `showmode` - command/mode display (handled by lualine)
- `showtabline = 1` - tabline visibility (handled by bufferline)
- `sidescroll = 1` - horizontal scroll amount
- `smoothscroll` - smooth scrolling (vim 9.0+ feature)
- `nostartofline` - cursor column preservation
- `tildeop` - tilde as operator
- `titlelen = 95`, `titlestring` - detailed title customization (using default)
- `viewoptions+=unix,slash` - view file options
- `viminfo` removable media flags (`rA:,rB:,r/tmp`) - not needed for typical workflows
- `virtualedit = ""` - not explicitly set (defaults to empty)
- `whichwrap = b,s,>,<,~,],[` - cursor wrapping at line boundaries
- `wildignorecase` - case-insensitive command completion
- `wildmode = noselect:lastused,full` - using default wildmode
- `wildcharm = <C-@>` - using for auto-completion trigger in kennypete's config
- `winheight = 3`, `winminheight = 3` - window height constraints
- `autoindent` - enabled by `filetype indent on` in modern configs
- `nrformats = alpha,hex,bin,unsigned` - number formats for increment/decrement
- `modeline` - enable modelines (security consideration)
- `fillchars+=lastline:@` - last line indicator (using default)

## missing but should add

### high value options to consider adding

```lua
-- neovim (home/config/nvim/lua/ext/options.lua)
o.showcmd = true           -- show partial commands
o.showmode = false         -- mode shown in statusline already
vim.opt.shortmess:append("I")  -- no intro message (from "inxtToOs")
```

```vim
" classic vim (home/config/vimrc)
set showcmd                " show partial commands
set shortmess+=I           " no intro message
set autoindent             " auto-indent new lines
```

### wsl-specific (add if on wsl)

```vim
" prevent replace mode in wsl
set t_u7=
```

## fillchars difference

**kennypete**: `vert:⏽,fold:-,eob:~,foldopen:┏,foldsep:│,foldclose:╋,lastline:@`
**ours**: `vert:│,fold:-,eob:~,foldopen:┏,foldsep:│,foldclose:╋`

changed `vert:⏽` to `vert:│` for better terminal compatibility.

## viminfo/shada difference

**kennypete**: `'100,<9999,s1000,h,rA:,rB:,r/tmp`
**ours**: `'100,<9999,s1000,h`

removed removable media flags (`rA:`, `rB:`, `r/tmp`) - not needed for typical workflows.

## summary

most differences are intentional:
1. **modern workflow additions** - lsp integration, plugin compatibility
2. **removed vim9-specific options** - keeping config compatible across vim versions
3. **removed specialized options** - printing, folding, advanced session management (using plugins instead)
4. **environment-specific exclusions** - wsl terminal fixes, removable media handling

the core kennypete philosophy (visual feedback, extended history, smart defaults) is preserved while adapting to a plugin-enhanced neovim environment.
