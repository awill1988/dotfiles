final: prev:
let
  version = "0.147.0";

  # platform-specific binary info
  # upstream switched linux artifacts from -gnu to -musl in the rust-v0.122.0+ releases
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-dZhLgfkqcbDA9LO1ytgOXFcXfk2Mi0seE9twOyDcQ1g=";
      hostHash = "sha256-Vs2/YYe/kUEI07f+7qWjT/uhXlwWK+3OaeBi7pLd+14=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-NueC9x2BZMw3wricZJSPIYDpovhFayfmYNp1vGtVdOI=";
      hostHash = "sha256-f3q8r3hSKRQ3wOaQIULqdtJqbrjaaYpBWcYDQTrBuJ0=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-musl";
      hash = "sha256-Akbi53ODTgfw+1JJ7W660S5FkeYI+Me7l91qlpBUTDY=";
      hostHash = "sha256-AUat+qyDY+yfzbWJX3Yk21suhheig4h5OLf7l6HdQ1Y=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-musl";
      hash = "sha256-62d8gPZmsauLSx0IO2bo1hSxKB2WC7b5/Yypj1izi5A=";
      hostHash = "sha256-/aRWNRp24Eswsfsa92VDqejI3z8MVndhoIlbdJRM4V0=";
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
