{
  claude = import ./claude.nix;
  codex = import ./codex.nix;
  fivetran-mcp-server = import ./fivetran-mcp-server.nix;
  gemini = import ./gemini.nix;
  github-mcp-server = import ./github-mcp-server.nix;
  rustup = import ./rustup.nix;
}
