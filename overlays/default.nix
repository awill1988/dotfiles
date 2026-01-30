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
  # disable wxwidgets support in erlang to avoid webkitgtk build
  erlang-no-wx =
    final: prev:
    let
      erlang_28_no_wx = prev.beam.interpreters.erlang_28.override { wxGTK32 = null; };
      beamPackages_28_no_wx = prev.beam.packagesWith erlang_28_no_wx;
    in
    {
      erlang_28 = erlang_28_no_wx;
      beam = prev.beam // {
        packages = prev.beam.packages // {
          erlang_28 = beamPackages_28_no_wx;
        };
      };
    };
  rustup = import ./rustup.nix;
}
