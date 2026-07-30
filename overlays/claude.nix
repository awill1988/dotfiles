final: prev:
let
  version = "2.1.220";

  platform_info = {
    aarch64-darwin = {
      artifact = "claude-darwin-arm64.tar.gz";
      hash = "sha256-HIldPXqXzB69RXovZLogISR23oJGjko/wUK+7uJw5V4=";
    };
    x86_64-darwin = {
      artifact = "claude-darwin-x64.tar.gz";
      hash = "sha256-PJByI58F/dTKagKljYkvLM8EYP9+XJSpyI1l6zOD2hY=";
    };
    x86_64-linux = {
      artifact = "claude-linux-x64.tar.gz";
      hash = "sha256-5p5/cteEwkO8w3eleK2f+OZa4U2mcvu/nyunv0fsp+w=";
    };
    aarch64-linux = {
      artifact = "claude-linux-arm64.tar.gz";
      hash = "sha256-pPLpNiGxUhcx0fEyyD+CZjhEA6sp4UmG1n47SoBb9FQ=";
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
