final: prev:
let
  version = "0.141.0";

  # platform-specific binary info
  # upstream switched linux artifacts from -gnu to -musl in the rust-v0.122.0+ releases
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-q96tX+68JZ3squwzRlQju7eQSzBJ+ijpIgnLkkaTwPQ=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-e3OYuT3RajEjyHKG4xKnlCvjwT+WGfxYffwFVj/LyIg=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-musl";
      hash = "sha256-8eK/n6C6brghGdYhtrcbw47dM8BtwoZ7MaAnBSNYlX0=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-musl";
      hash = "sha256-jJ8xgR1ln8wXxfGiG8CXGYRGnJ46Y8Kzm2HMdpTzoQE=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${info.suffix}.tar.gz";
    hash = info.hash;
  };

in
{
  codex = final.stdenv.mkDerivation {
    pname = "codex";
    inherit version src;

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    # linux artifacts are statically linked musl binaries; macos uses mach-o.
    # neither needs autoPatchelfHook or runtime buildInputs.

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
