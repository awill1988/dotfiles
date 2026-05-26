final: prev:
let
  version = "2.1.150";
  gcs_bucket = "https://storage.googleapis.com/claude-code-dist-86c565f3-f756-42ad-8dfa-d59b1c096819/claude-code-releases";

  # platform-specific binary info (native installer)
  platform_info = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      sha256 = "2f8413ea1083f108587940496a17057751344109d261fb4239ab2d45b2285c99";
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      sha256 = "c66d5721df38cce82cde03d244f8fa92768125fe06e8d1d38d4bfbadaf4a8d17";
    };
    x86_64-linux = {
      platform = "linux-x64";
      sha256 = "6c086a0f5fbf684d4148bb69629268b4f5109498c1a7be757acf18c51fd04f4b";
    };
    aarch64-linux = {
      platform = "linux-arm64";
      sha256 = "2052949543ea076e2b5cda44c031b2b34fc303db98dc56ad6583b7e0a417ebeb";
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
