{ pkgs, ... }:
{
  programs.nix-index.enable = true;

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "qgis";
      text = ''
        if [ ! -d "/Applications/QGIS.app" ]; then
          echo "qgis is not installed; apply the darwin configuration first" >&2
          exit 1
        fi

        exec /usr/bin/open -a QGIS "$@"
      '';
    })
  ];
}
