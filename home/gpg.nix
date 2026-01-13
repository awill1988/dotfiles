{ config, pkgs, lib, ... }:
let inherit (config.home) user-info;
in {
  programs.gpg =
    let
      common = {
        enable = true;
        settings = { }
          // lib.optionalAttrs (!builtins.isNull user-info.git.signingKey) {
          default-key = user-info.git.signingKey;
          auto-key-locate = "keyserver";
          keyserver = "pgp.mit.edu";
          keyserver-options =
            "no-honor-keyserver-url include-revoked auto-key-retrieve";

          # Use AES256, 192, or 128 as cipher
          personal-cipher-preferences = "AES256 AES192 AES";
          # Use SHA512, 384, or 256 as digest
          personal-digest-preferences = "SHA512 SHA384 SHA256";
          # Use ZLIB, BZIP2, ZIP, or no compression
          personal-compress-preferences = "ZLIB BZIP2 ZIP Uncompressed";
          # Default preferences for new keys
          default-preference-list =
            "SHA512 SHA384 SHA256 AES256 AES192 AES ZLIB BZIP2 ZIP Uncompressed";
          # SHA512 as digest to sign keys
          cert-digest-algo = "SHA512";
          # SHA512 as digest for symmetric ops
          s2k-digest-algo = "SHA512";
          # AES256 as cipher for symmetric ops
          s2k-cipher-algo = "AES256";
          # UTF-8 support for compatibility
          charset = "utf-8";
          # Show Unix timestamps
          fixed-list-mode = true;
          # No comments in signature
          no-comments = true;
          # No version in output
          no-emit-version = true;
          # Disable banner
          no-greeting = true;
          # Long hexidecimal key format
          keyid-format = "0xlong";
          # Display UID validity
          list-options = "show-uid-validity";
          verify-options = "show-uid-validity";
          # Display all keys and their fingerprints
          with-fingerprint = true;
          # Cross-certify subkeys are present and valid
          require-cross-certification = true;
          # Disable caching of passphrase for symmetrical ops
          no-symkey-cache = true;
          # Enable smartcard
          use-agent = true;
          # Disable recipient key ID in messages
          throw-keyids = true;
        };
        scdaemonSettings = {
          # use pcscd for shared access (allows ykman + gpg concurrently)
          disable-ccid = true;
          pcsc-driver = "${pkgs.pcsclite.lib}/lib/libpcsclite.so.1";
          card-timeout = "1";
        };
      };
      darwin = lib.optionalAttrs pkgs.stdenv.isDarwin { enable = false; };
    in
    common // darwin;

  services.gpg-agent = {
    enable = true;
    enableSshSupport = true;
    defaultCacheTtl = 8 * 60 * 60; # 8 hours
    maxCacheTtl = 12 * 60 * 60; # 12 hours
    extraConfig = "allow-loopback-pinentry";
    pinentry = {
      package =
        if pkgs.stdenv.isDarwin then
          # use pinentry-mac (installed via homebrew cask)
          pkgs.writeShellScriptBin "pinentry" ''
            exec /opt/homebrew/bin/pinentry-mac "$@"
          ''
        else
          # prefer GUI pinentry when DISPLAY/WAYLAND is available; fallback to curses otherwise
          pkgs.writeShellScriptBin "pinentry" ''
            set -e
            if [ -n "''${DISPLAY:-}" ] || [ -n "''${WAYLAND_DISPLAY:-}" ]; then
              exec ${pkgs.pinentry-gtk2}/bin/pinentry-gtk-2 "$@"
            fi
            exec ${pkgs.pinentry-curses}/bin/pinentry-curses "$@"
          '';
    };
  };
}
