final: prev:
let
  version = "0.167.0";

  # platform-specific package info
  # upstream switched from bare binary tarballs to complete package bundles in rust-v0.157.0+
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-r0XtRdlA15mICWIsHAKW0wmO19f61pUoRCLCKL1FRRc=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-PXxMgylttjtRCOE2Esd/PlAgtsXy/ABL7kE6XMkt6Jk=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-musl";
      hash = "sha256-O7916D3mtYrtKPLPbjOtQj7DH9RwChRXuUvlV+pafG4=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-musl";
      hash = "sha256-DeJh7PHn8wKKeVLwP8ogk/dJJ304WQt4uzL4VndWu7c=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-package-${info.suffix}.tar.gz";
    hash = info.hash;
  };

in
{
  codex = final.stdenv.mkDerivation {
    pname = "codex";
    inherit version;

    inherit src;
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R * $out/
      chmod -R u+w $out
      chmod 755 $out/bin/*
      if [ -d $out/codex-path ]; then
        chmod 755 $out/codex-path/*
      fi
      ln -sf bin/codex $out/codex
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "OpenAI Codex CLI (prebuilt binary)";
      homepage = "https://github.com/openai/codex";
      license = licenses.asl20;
      mainProgram = "codex";
      platforms = [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      maintainers = [ ];
    };
  };
}
