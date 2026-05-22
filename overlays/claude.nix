final: prev:
let
  version = "2.1.143";
  gcs_bucket = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  # platform-specific binary info (native installer)
  platform_info = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      sha256 = "2701c6cfd68483f8faf0316a1ba6481a1455a90645ada179f0c48d8c36d722ef";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      sha256 = "bc8ff4ce02b765a033808fb596f9522306cbe5c50d21344ed8752c08966f362c";
    };
    x86_64-linux = {
      platform = "linux-x64";
      sha256 = "f75fdc3ff9d9cd494b86192f9e349b5c5c6d3970ed4d5cd5c7b330c5a2b1dcc4";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      sha256 = "32e8edc4a5c3c41d18607c75d1b8e7bec643330c03e266be46ac3b41a446c4eb";
    };
  };

  system = final.stdenv.hostPlatform.system;
  is_linux = final.stdenv.isLinux;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "${gcs_bucket}/${version}/${info.platform}/claude";
    sha256 = info.sha256;
  };
in
{
  claude = final.stdenv.mkDerivation {
    pname = "claude";
    inherit version src;

    nativeBuildInputs = [
      prev.makeWrapper
    ]
    ++ prev.lib.optionals is_linux [
      prev.autoPatchelfHook
    ];

    # runtime deps for autoPatchelfHook (linux only)
    buildInputs = prev.lib.optionals is_linux [
      prev.stdenv.cc.cc.lib
      prev.zlib
    ];

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = is_linux; # linux strip destroys embedded javascript

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      install -Dm755 $src $out/bin/claude

      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/bin/claude \
        --set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1
    '';

    meta = with prev.lib; {
      description = "Claude Code CLI (native binary)";
      homepage = "https://github.com/anthropics/claude-code";
      license = licenses.unfree;
      mainProgram = "claude";
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
