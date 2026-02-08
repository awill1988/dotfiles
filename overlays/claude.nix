final: prev:
let
  version = "2.1.37";
  gcs_bucket = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  # platform-specific binary info (native installer)
  platform_info = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      sha256 = "00ed10afb7a562440773de31284568ce9c33385d79d3a912a12af262aefd130e";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      sha256 = "5ad9639bf34affa47066fb98f2d7ad7b0f236009744d309077b194d896fc011d";
    };
    x86_64-linux = {
      platform = "linux-x64";
      sha256 = "f967a4d06e16a32436b6329e2dbed459a9fa4d34f07635a1fb271b74f706c91f";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      sha256 = "d725cc73060f400a7ac03a769969397daec9d411dbd5b1c7bb1fa60427bf657e";
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
