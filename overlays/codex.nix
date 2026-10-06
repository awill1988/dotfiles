final: prev:
let
  version = "0.160.1";

  # platform-specific package info
  # upstream switched from bare binary tarballs to complete package bundles in rust-v0.157.0+
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-9zUn7gnG24aay7N7cJhmsznqdO+R0t4lXpx07JYMYxQ=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-qY8zDJsWUs7y7ce8LuTEeg/hn6CYtoY4G+PIhCq/CsA=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-musl";
      hash = "sha256-NAgBVlkGpwKPa6qpq2hTrdrvIh8AFqFBenwf/dlsIfA=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-musl";
      hash = "sha256-3/CVRDj6RVwhl92x9CHY1oYl2Y3mEPdr7bblvIN+o1s=";
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
