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
    exec ${python}/bin/python ${src} "$@"
  '';
}
