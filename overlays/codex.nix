final: prev:
let
  version = "0.89.0";

  # platform-specific binary info
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-hoRaw3UWpS0npu2gWlWpL6+EZ5qP9uSalChDw0PC2eM=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-Nsu4F1CW2OaR9mFu0Kq8YWsnvSBNWK/iAIDN1v/834g=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-gnu";
      hash = "sha256-AlfFJBp2qULdcv/IbloGd8JBQCZtOzCQLM1nQfugccc=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-gnu";
      hash = "sha256-rB0oHx5I/nO4nK3nprNQ1RuSfsB4V0q5FGpFFeRmVE4=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${info.suffix}.tar.gz";
    hash = info.hash;
  };

  is_linux = final.stdenv.hostPlatform.isLinux;
in
{
  codex = final.stdenv.mkDerivation {
    pname = "codex";
    inherit version src;

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    # autoPatchelfHook is linux-only (elf binaries); macos uses mach-o
    nativeBuildInputs = final.lib.optionals is_linux [ prev.autoPatchelfHook ];
    buildInputs = final.lib.optionals is_linux [
      prev.openssl
      prev.stdenv.cc.cc.lib
    ];

    installPhase = ''
      runHook preInstall
      install -Dm755 codex-${info.suffix} $out/bin/codex
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
