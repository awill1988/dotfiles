final: prev:
let
  version = "0.75.0";
  src = prev.fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    rev = "rust-v${version}";
    hash = "sha256-XsFJjXFBsj8jeOMLuP+sMW1ZiAQIuL+XBFjUhgCLJmU=";
  };

  is_linux = final.stdenv.hostPlatform.isLinux;
  rust_toolchain =
    if final ? rust-bin && final.rust-bin ? stable
      && builtins.hasAttr "1.90.0" final.rust-bin.stable then
      final.rust-bin.stable."1.90.0".default
    else
      null;

  cargo_toolchain =
    if rust_toolchain != null then rust_toolchain else final.cargo;
  rustc_toolchain =
    if rust_toolchain != null then rust_toolchain else final.rustc;

  rust_platform = final.makeRustPlatform {
    # prefer glibc on linux; keep the platform default elsewhere
    stdenv = if is_linux then final.gccStdenv else final.stdenv;
    cargo = cargo_toolchain;
    rustc = rustc_toolchain;
  };
in
{
  codex = rust_platform.buildRustPackage {
    pname = "codex";
    inherit version src;
    sourceRoot = "source/codex-rs";
    cargoHash = "sha256-9zf9xpnh9w3DWizLSHUR2CfN+E9fYxamKkyMLkYiIP8=";
    nativeBuildInputs = [ final.pkg-config ];
    buildInputs = [ final.openssl final.dbus ];

    cargoBuildFlags = [ "-p" "codex-cli" ];
    doCheck = false;
    # rustc needs a larger stack; 2 GiB
    RUST_MIN_STACK = "2147483648";
    # upstream enables thin LTO in Cargo profiles; disable to avoid linux build crashes
    CARGO_PROFILE_RELEASE_LTO = "off";
    # increase codegen units to reduce memory usage (default: 16)
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
