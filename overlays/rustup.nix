final: prev:
let
  version = "1.28.2";

  platform_info = {
    aarch64-darwin = {
      target = "aarch64-apple-darwin";
      hash = "sha256-IO9VFsMbGsIpAIQZm6d9u8qhQGxFwdl4ymhVjvWWTvU=";
    };
    x86_64-darwin = {
      target = "x86_64-apple-darwin";
      hash = "sha256-nDMQdvYrTQ7ermPZ0clELV/jmzewUCXsjUHF7TVIZJY=";
    };
    x86_64-linux = {
      target = "x86_64-unknown-linux-gnu";
      hash = "sha256-IKBuZEsNm9L72/1S1CVAvd6CDqffhukuUzwHPaDN1Dw=";
    };
    aarch64-linux = {
      target = "aarch64-unknown-linux-gnu";
      hash = "sha256-44U8WiUvyhUlLQfLI6G92Td6jG8++gFTEQkoGuR/hBw=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  is_linux = final.stdenv.isLinux;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://static.rust-lang.org/rustup/archive/${version}/${info.target}/rustup-init";
    hash = info.hash;
  };
in
{
  rustup = final.stdenv.mkDerivation {
    pname = "rustup";
    inherit version src;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = final.lib.optionals is_linux [ prev.autoPatchelfHook ];
    buildInputs = final.lib.optionals is_linux [
      prev.stdenv.cc.cc.lib
      prev.zlib
      prev.curl
    ];

    installPhase = ''
      runHook preInstall
      # argv[0] = "rustup" -> toolchain manager mode
      # argv[0] = "rustup-init" -> installer mode
      install -Dm755 $src $out/bin/rustup

      # rustup dispatches on argv[0]; symlinks let nix provide
      # all proxy commands without running rustup-init setup
      for proxy in \
        cargo cargo-clippy cargo-fmt cargo-miri \
        clippy-driver rust-analyzer rust-gdb rust-lldb \
        rustc rustdoc rustfmt; do
        ln -s rustup "$out/bin/$proxy"
      done
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Rust toolchain manager (prebuilt binary)";
      homepage = "https://rustup.rs";
      license = with licenses; [
        asl20
        mit
      ];
      mainProgram = "rustup";
      platforms = builtins.attrNames platform_info;
      maintainers = [ ];
    };
  };
}
