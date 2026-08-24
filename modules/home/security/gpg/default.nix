{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.security.gpg;
  resolvedProfilesList = attrValues config.developer.resolvedProfiles;
  primaries = filter (p: p.isPrimary) resolvedProfilesList;
  primaryProfile =
    if primaries != [ ] then
      head primaries
    else if resolvedProfilesList != [ ] then
      head resolvedProfilesList
    else
      null;
  signingKey = if primaryProfile != null then primaryProfile.identity.signingKey else null;
in
{
  options.modules.security.gpg = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable GPG configuration and gpg-agent service.";
    };
  };

  config = mkIf cfg.enable {
    programs.gpg =
      let
        common = {
          enable = true;
          settings =
            { }
            // optionalAttrs (!builtins.isNull signingKey) {
              default-key = signingKey;
              auto-key-locate = "keyserver";
              keyserver = "pgp.mit.edu";
              keyserver-options = "no-honor-keyserver-url include-revoked auto-key-retrieve";

              personal-cipher-preferences = "AES256 AES192 AES";
              personal-digest-preferences = "SHA512 SHA384 SHA256";
              personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
              default-preference-list = "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";
              cert-digest-algo = "SHA512";
              s2k-digest-algo = "SHA512";
              s2k-cipher-algo = "AES256";
              charset = "utf-8";
              fixed-list-mode = true;
              no-comments = true;
              no-emit-version = true;
              no-greeting = true;
              keyid-format = "0xlong";
              list-options = "show-uid-validity";
              verify-options = "show-uid-validity";
              with-fingerprint = true;
              require-cross-certification = true;
              no-symkey-cache = true;
              use-agent = true;
              throw-keyids = true;
            };
          scdaemonSettings = {
            disable-ccid = true;
            pcsc-driver = "${pkgs.pcsclite.lib}/lib/libpcsclite.so.1";
            card-timeout = "1";
          };
        };
        darwin = optionalAttrs pkgs.stdenv.isDarwin { enable = false; };
      in
      common // darwin;

    services.gpg-agent = {
      enable = true;
      enableSshSupport = true;
      defaultCacheTtl = 8 * 60 * 60;
      maxCacheTtl = 12 * 60 * 60;
      extraConfig = "allow-loopback-pinentry";
      pinentry = {
        package =
          if pkgs.stdenv.isDarwin then
            pkgs.writeShellScriptBin "pinentry" ''
              exec /opt/homebrew/bin/pinentry-mac "$@"
            ''
          else
            pkgs.writeShellScriptBin "pinentry" ''
              set -e
              if [[ -f /proc/version ]] && [[ "$(< /proc/version)" == *[Mm]icrosoft* ]]; then
                for win_pinentry in \
                  "/mnt/c/Program Files/Git/usr/bin/pinentry.exe" \
                  "/mnt/c/Program Files (x86)/GnuPG/bin/pinentry.exe" \
                  "/mnt/c/Program Files/GnuPG/bin/pinentry.exe" \
                  "/mnt/c/Program Files (x86)/Gpg4win/bin/pinentry.exe" \
                  "/mnt/c/Program Files/Gpg4win/bin/pinentry.exe"; do
                  if [ -x "$win_pinentry" ]; then
                    exec "$win_pinentry" "$@"
                  fi
                done
              fi

              if [ -n "''${DISPLAY:-}" ] || [ -n "''${WAYLAND_DISPLAY:-}" ]; then
                exec ${pkgs.pinentry-gtk2}/bin/pinentry-gtk-2 "$@"
              fi
              exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@"
            '';
      };
    };
  };
}
