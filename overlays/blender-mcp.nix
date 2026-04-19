final: prev:
let
  version = "1.5.5";
  # ahujasid/blender-mcp has no release tags upstream; pin to commit on main.
  rev = "7636d13bded82eca58eb93c3f4cd8708dfdfbe8b";

  src = final.fetchFromGitHub {
    owner = "ahujasid";
    repo = "blender-mcp";
    inherit rev;
    hash = "sha256-VGilcq/ZuX5ancdUqQpc6z7LGoBpyCMIasaTIzmTbRM=";
  };

  # deps mirror upstream pyproject.toml: mcp[cli]>=1.3.0, supabase>=2.0.0, tomli>=2.0.0
  python = final.python312.withPackages (ps: [
    ps.mcp
    ps.supabase
    ps.tomli
  ]);

  # entry point is blender_mcp.server:main; expose as blender-mcp-unwrapped so
  # the home-manager wrapper can layer the fail-fast tcp probe in front of it.
  unwrapped = final.writeShellScriptBin "blender-mcp-unwrapped" ''
    set -euo pipefail
    export PYTHONPATH=${src}/src:''${PYTHONPATH:-}
    exec ${python}/bin/python -m blender_mcp.server "$@"
  '';
in
{
  blender-mcp = unwrapped.overrideAttrs (_: {
    passthru = {
      # addon.py lives at the repo root; consumed by the home-manager module
      # to symlink into ~/Library/Application Support/Blender/<ver>/scripts/addons.
      addon = "${src}/addon.py";
      pythonEnv = python;
      inherit src version;
    };
  });
}
