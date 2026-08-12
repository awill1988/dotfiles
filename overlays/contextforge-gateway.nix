# builds a virtualenv containing mcp-contextforge-gateway and snowflake-labs-mcp
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
    workspaceRoot = ../modules/home/programs/contextforge/pyproject;
  };

  overlay = workspace.mkPyprojectOverlay { sourcePreference = "wheel"; };

  python = final.python3;

  # backport v1.0.0-RC-3 fix to 0.9.0: skip empty HTTP 202 responses
  # when forwarding notifications (e.g. notifications/initialized).
  # without this, an empty json body triggers make_error which emits a
  # spurious {"id":"bridge"} parse error on stdout, corrupting the
  # mcp client's post-init state and suppressing tools/list.
  wrapper_patch = final': prev': {
    mcp-contextforge-gateway = prev'.mcp-contextforge-gateway.overrideAttrs (old: {
      postInstall = (old.postInstall or "") + ''
        wrapper_py=$out/${python.sitePackages}/mcpgateway/wrapper.py
        old_block=$(printf '%s\n%s' \
          '                text = raw.decode("utf-8", errors="replace")' \
          '                try:')
        new_block=$(printf '%s\n%s\n%s\n%s' \
          '                text = raw.decode("utf-8", errors="replace")' \
          '                if not text.strip():' \
          '                    return' \
          '                try:')
        substituteInPlace "$wrapper_py" --replace-fail "$old_block" "$new_block"
      '';
    });
  };

  pythonSet =
    (final.callPackage pyproject-nix.build.packages {
      inherit python;
    }).overrideScope
      (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.wheel
          overlay
          wrapper_patch
        ]
      );
in
{
  # install only the real packages, not the dummy contextforge-nix wrapper
  contextforge-gateway-env = pythonSet.mkVirtualEnv "contextforge-gateway-env" {
    mcp-contextforge-gateway = [ ];
    snowflake-labs-mcp = [ ];
  };
}
