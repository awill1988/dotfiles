final: prev:
let
  version = "0.133.0";

  # platform-specific binary info
  # upstream switched linux artifacts from -gnu to -musl in the rust-v0.122.0+ releases
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-E8eDYr7/gUt93hbtdWN2I2d3Zphp3eRL0jJnNQDfaFM=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-K5G9VPBSDcmUtcMidpKA+U8cIn/bNd1V+STqyOIke5E=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-musl";
      hash = "sha256-0GAZq5w10oG3jcLrsq5VwruX6hG/f0Urr+OQ7dsANO8=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-musl";
      hash = "sha256-Jov+jPgVSUD+olbfdc1EHFSgxx5sjM1Fqz92/yi6FBM=";
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
