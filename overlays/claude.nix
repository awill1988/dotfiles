final: prev:
let
  version = "2.1.19";
  gcs_bucket = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  # platform-specific binary info (native installer)
  platform_info = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      hash = "sha256-04asj20UefhdMfNpQhyCQTXBAknDIIcBfQWl9CiFLEE=";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      hash = "sha256-viZrOpkvSIPYNYrRQeCvphFwOGUGb0eeathpMZ5NjhM=";
    };
    x86_64-linux = {
      platform = "linux-x64";
      hash = "sha256-Tiocc4cezzsTM3a1fe0DMzp6Y4fy0qOmJ5u5Cgf3qUQ=";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      hash = "sha256-jEthskynYNb3qqLxlydjHRIun9DDzpHxBqIbaRiLG7s=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "${gcs_bucket}/${version}/${info.platform}/claude";
    hash = info.hash;
  };
in
{
  claude = final.stdenv.mkDerivation {
    pname = "claude";
    inherit version src;

    nativeBuildInputs = [ prev.makeWrapper ];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      install -Dm755 $src $out/libexec/claude

      makeWrapper $out/libexec/claude $out/bin/claude \
        --set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1

      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Claude Code CLI (native binary)";
      homepage = "https://github.com/anthropics/claude-code";
      license = licenses.unfree;
      mainProgram = "claude";
      platforms = [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      maintainers = [ ];
    };
  };
}
