{
  claude = import ./claude.nix;
  codex = import ./codex.nix;
  fivetran-mcp-server = import ./fivetran-mcp-server.nix;
  gemini = import ./gemini.nix;
  github-mcp-server = import ./github-mcp-server.nix;
  # disabled: breaks darwin stdenv bootstrap (llvm packages must come from bootstrap files)
  # llvm-xcode = final: prev: { ... };
  libsecret = final: prev: {
    libsecret = prev.libsecret.override {
      withIntrospection = false;
    };
  };
  rustup = import ./rustup.nix;
}
