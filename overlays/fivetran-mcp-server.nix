final: prev:
let
  version = "unstable-2025-01-21";

  src = final.fetchurl {
    url = "https://raw.githubusercontent.com/fivetran/api_framework/37618e5651d5921c0ba4bfd22b404f522e1feb06/examples/mcp/local/mcp_example.py";
    hash = "sha256-3vvEd5SEz6SX469n2Thsn5j4+ox13RJR+7kDVtT4K50=";
  };

  python = final.python312.withPackages (ps: [
    ps.mcp
    ps.requests
  ]);
in
{
  # mcp → aiohttp → gunicorn → setproctitle; tests segfault on darwin/arm64 + python 3.13
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      setproctitle = python-prev.setproctitle.overrideAttrs (old: {
        doCheck = false;
        doInstallCheck = false;
      });
    })
  ];

  fivetran-mcp-server = final.writeShellScriptBin "fivetran-mcp-server" ''
    set -euo pipefail

    if [[ -z "''${FIVETRAN_API_KEY:-}" || -z "''${FIVETRAN_API_SECRET:-}" ]]; then
      echo "error: FIVETRAN_API_KEY and FIVETRAN_API_SECRET must be set" >&2
      exit 1
    fi

    # create runtime config in user-writable location
    config_dir="''${XDG_RUNTIME_DIR:-/tmp}/fivetran-mcp"
    config_file="$config_dir/configuration.json"
    mkdir -p "$config_dir"
    cat > "$config_file" <<EOF
    {
      "fivetran_api_key": "$FIVETRAN_API_KEY",
      "fivetran_api_secret": "$FIVETRAN_API_SECRET"
    }
    EOF
    chmod 600 "$config_file"

    # patch script to use our config path instead of /mcp/configuration.json
    patched_script="$config_dir/mcp_server.py"
    ${final.gnused}/bin/sed "s|/mcp/configuration.json|$config_file|g" ${src} > "$patched_script"

    exec ${python}/bin/python "$patched_script" "$@"
  '';
}
