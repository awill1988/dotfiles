# builds a virtualenv containing mcp-contextforge-gateway
# from a uv.lock pinned in the repo.  replaces runtime `uvx` compilation.
{
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
final: prev:
let
  inherit (final) lib;

  workspace = uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = ../modules/home/agents/agent-tools/contextforge/pyproject;
  };

  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  python = final.python313;

  pythonSet =
    (final.callPackage pyproject-nix.build.packages {
      inherit python;
    }).overrideScope
      (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.wheel
          overlay
        ]
      );
in
{
  # install only the real packages, not the dummy contextforge-nix wrapper
  contextforge-gateway-env = pythonSet.mkVirtualEnv "contextforge-gateway-env" {
    mcp-contextforge-gateway = [ ];
    fastmcp-remote = [ ];
  };
}
