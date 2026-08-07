final: prev:
let
  version = "2.1.224";

  platform_info = {
    aarch64-darwin = {
      artifact = "claude-darwin-arm64.tar.gz";
      hash = "sha256-egIoyVuKXVrAiMA8/jgQ+s2d6JND3EqJLcechBrsFBY=";
    };
    x86_64-darwin = {
      artifact = "claude-darwin-x64.tar.gz";
      hash = "sha256-0bV25HfbJi1FcFsaHzVCxP44Abl2KnxloSUHKcFZT3g=";
    };
    x86_64-linux = {
      artifact = "claude-linux-x64.tar.gz";
      hash = "sha256-ddb2S80tFrrQglqOjHRnAlE7N1xHSEo3PwsFf/SZGOc=";
    };
    aarch64-linux = {
      artifact = "claude-linux-arm64.tar.gz";
      hash = "sha256-b3IYjTWTERtKjm1ziEQgnOQvlCdfnVmB8xI9RipmwVc=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  is_linux = final.stdenv.isLinux;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url =
      "https://github.com/anthropics/claude-code/releases/download/v${version}/${info.artifact}";
    hash = info.hash;
  };
in {
  claude = final.stdenv.mkDerivation {
    pname = "claude";
    inherit version src;

    nativeBuildInputs = [ prev.makeWrapper ]
      ++ prev.lib.optionals is_linux [ prev.autoPatchelfHook ];

    # runtime deps for autoPatchelfHook (linux only)
    buildInputs =
      prev.lib.optionals is_linux [ prev.stdenv.cc.cc.lib prev.zlib ];

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontStrip = is_linux; # linux strip destroys embedded javascript

    unpackPhase = ''
      tar -xzf "$src"
    '';

    installPhase = ''
      runHook preInstall

      install -Dm755 claude $out/bin/claude

      runHook postInstall
    '';

    postFixup = ''
      wrapProgram $out/bin/claude \
        --set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC 1 \
        --set DO_NOT_TRACK 1
    '';

    meta = with prev.lib; {
      description = "Claude Code CLI (native binary)";
      homepage = "https://github.com/anthropics/claude-code";
      license = licenses.unfree;
      mainProgram = "claude";
      platforms =
        [ "aarch64-darwin" "x86_64-darwin" "x86_64-linux" "aarch64-linux" ];
      maintainers = [ ];
    };
  };
}
