final: prev:
let
  version = "0.107.0";

  # platform-specific binary info
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-TmVDaTSbFF2vAnyWOm7Vqjv5pd8dtf/7ULZO1jvF/Dk=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-p8WCclILa34i3qic3zSmWQjeAVU4aGuoY3Ej/W6rdRk=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-gnu";
      hash = "sha256-Up1p93xQH6z7HN5Fnihfc8CmQdUHn3u00/ESycIqbSU=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-gnu";
      hash = "sha256-WXAHjFZgVv240eCdZifCuy3ZCqRNkERVtu0McqcRGKs=";
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
