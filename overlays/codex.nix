final: prev:
let
  version = "0.67.0-alpha.8";
  src = prev.fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = "rust-v${version}";
    hash = "sha256-xy2lkyAcpDY6R0wmQh1jZSU5kDKBrqZoqh694dif5iU=";
  };

  rust_toolchain =
    if final ? rust-bin && final.rust-bin ? nightly
       && final.rust-bin.nightly ? latest
       && final.rust-bin.nightly.latest ? default then
      final.rust-bin.nightly.latest.default
    else
      null;

  cargo_toolchain =
    if rust_toolchain != null then rust_toolchain else final.cargo;
  rustc_toolchain =
    if rust_toolchain != null then rust_toolchain else final.rustc;

  rust_platform = final.makeRustPlatform {
    cargo = cargo_toolchain;
    rustc = rustc_toolchain;
  };
in {
  codex = rust_platform.buildRustPackage {
    pname = "codex";
    inherit version src;
    sourceRoot = "source/codex-rs";
    cargoHash = "sha256-X5eN4xh900kdrMvdOBHZdHsd3fP2kW2rc59+SxTrlss=";
    nativeBuildInputs = [ final.pkg-config ];
    buildInputs = [ final.openssl final.dbus ];

    cargoBuildFlags = [ "-p" "codex-cli" ];
    RUST_MIN_STACK = "134217728";
    RUSTFLAGS = "-C lto=off -C codegen-units=16";
    CARGO_PROFILE_RELEASE_LTO = "false";
    CARGO_PROFILE_RELEASE_CODEGEN_UNITS = "16";
    auditable = false;
    preBuild = ''unset RUSTC_WRAPPER'';
    meta = with final.lib; {
      description = "OpenAI Codex CLI built from source";
      homepage = "https://github.com/openai/codex";
      license = licenses.asl20;
      mainProgram = "codex";
      platforms = platforms.unix;
      maintainers = [ ];
    };
  };
}
