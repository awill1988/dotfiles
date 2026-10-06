final: prev:
let
  version = "0.160.1";

  # platform-specific binary info
  # upstream switched linux artifacts from -gnu to -musl in the rust-v0.122.0+ releases
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-ZwrysEnZyVr7dNfaOF8wxQM9E6BxdQAd2JWMUZRJhNA=";
      hostHash = "sha256-blAt9p2SIPowWww8fBe6jzGrHUWR/BQAhNu4I+gAx9s=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-jZON25PEQksdRfFgaYTtUUxapw5GMwKmoiJ/unrwLbc=";
      hostHash = "sha256-zQrmfhwsbKucBl4yh6VvBolhxVkuEUwczW6aSQm7oUc=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-musl";
      hash = "sha256-kiZYG+WS0Y9+f3QKNS/bY6ph5F459+ubCdOIjIS7oz8=";
      hostHash = "sha256-imkgfZdUWsdTtlhZdOHmekxRrl3qzwZRfbUSuyXg48I=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-musl";
      hash = "sha256-9U3FhSBCRFv0HaOqMRVvPLAvUsWhoEB03nPcVZj34fc=";
      hostHash = "sha256-5eAn5mie/aLjVwqmABefDrsYYygDNQ4VLtbJuX3Pl0E=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${info.suffix}.tar.gz";
    hash = info.hash;
  };

  # Host binary for Code Mode execution
  hostSrc = final.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-code-mode-host-${info.suffix}.tar.gz";
    hash = info.hostHash or "";
  };

in
{
  codex = final.stdenv.mkDerivation {
    pname = "codex";
    inherit version;

    srcs = [
      src
      hostSrc
    ];
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 codex-${info.suffix} $out/bin/codex
      if [ -f codex-code-mode-host-${info.suffix} ]; then
        install -Dm755 codex-code-mode-host-${info.suffix} $out/bin/codex-code-mode-host
      fi
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
