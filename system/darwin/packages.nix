{ pkgs, ... }:
{
  programs.nix-index.enable = true;

  environment.systemPackages = [
    (pkgs.writeShellApplication {
      name = "qgis";
      text = ''
        qgis_application=""
        for candidate in /Applications/QGIS.app /Applications/QGIS*.app "$HOME/Applications/QGIS.app" "$HOME/Applications/QGIS*.app"; do
          if [ -d "$candidate" ]; then
            qgis_application="$candidate"
            break
          fi
        done

        if [ -z "$qgis_application" ]; then
          echo "qgis is not installed; apply the darwin configuration first" >&2
          exit 1
        fi

        if [ "$#" -gt 0 ]; then
          if [ -x "$qgis_application/Contents/MacOS/QGIS" ]; then
            exec "$qgis_application/Contents/MacOS/QGIS" "$@"
          elif [ -x "$qgis_application/Contents/MacOS/QGIS-bin" ]; then
            exec "$qgis_application/Contents/MacOS/QGIS-bin" "$@"
          else
            exec /usr/bin/open -a "$qgis_application" --args "$@"
          fi
        else
          exec /usr/bin/open -a "$qgis_application"
        fi
      '';
    })
  ];
}
