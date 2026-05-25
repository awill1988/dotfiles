{
  blender-mcp = import ./blender-mcp.nix;
  cf2tf = import ./cf2tf.nix;
  claude = import ./claude.nix;
  codex = import ./codex.nix;
  drawio-mcp = import ./drawio-mcp.nix;
  fivetran-mcp-server = import ./fivetran-mcp-server.nix;
  gemini = import ./gemini.nix;
  agy = import ./agy.nix;
  github-mcp-server = import ./github-mcp-server.nix;
  hunyuan3d-2 = import ./hunyuan3d-2.nix;
  mtkclient = import ./mtkclient.nix;
  libsecret = final: prev: {
    libsecret = prev.libsecret.override {
      withIntrospection = false;
    };
  };
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
