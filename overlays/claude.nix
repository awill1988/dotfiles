final: prev:
let
  version = "2.1.63";
  gcs_bucket = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  # platform-specific binary info (native installer)
  platform_info = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      sha256 = "2e8667322e0bd104087df2a8857f176acc75d7091aa02828825dfeb4a5708531";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      sha256 = "07842d6521f59bc68979d833ef33cbc1b985b9f5e09fa8975efe039989666aa9";
    };
    x86_64-linux = {
      platform = "linux-x64";
      sha256 = "734447e461bb92f0ffd5f683bb6216c35a3c16e8dd84be8d150b43605d39b0d1";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      sha256 = "1fec8c8369606b4a6c00af963354b7d48aee793ed5db378fe4cf280149f3190a";
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
