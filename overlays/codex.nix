final: prev:
let
  version = "0.98.0";

  # platform-specific binary info
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-PMdXcogDruDEyZTFaCENmQCrxs7GC+Aj57LApuMBglU=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-3TbAn2eJKapd/StIzqP5PGuLEzkafQV1BSH99GUofEo=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-gnu";
      hash = "sha256-Hy4JfXeItUkuGgkvT40i9OxT88bZrYtD2R4vzsD4yj8=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-gnu";
      hash = "sha256-MhFwVo/ltOutfxCrl5A+BJNEhnqTsHLzP/YO3YYxA40=";
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
