final: prev:
let
  version = "2.1.322";

  platform_info = {
    aarch64-darwin = {
      artifact = "claude-darwin-arm64.tar.gz";
      hash = "sha256-D/OJ8aMT9Qd4wkcsL4WILKgsEBVjmMaM/DwzIARpRkY=";
    };
    x86_64-darwin = {
      artifact = "claude-darwin-x64.tar.gz";
      hash = "sha256-enKRxa4ByPjpHcJjbaQ/kFvTy1KxFwIphQ+D8/7xlOE=";
    };
    x86_64-linux = {
      artifact = "claude-linux-x64.tar.gz";
      hash = "sha256-PSvFrlTU1M1jUQ6fzKW21I0rGIBnCN+Mj2kapIbF3Kg=";
    };
    aarch64-linux = {
      artifact = "claude-linux-arm64.tar.gz";
      hash = "sha256-ZcGtNegE70Y/NFhdDAgK/Uvy6QGMe60fKe+4306cN1A=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  is_linux = final.stdenv.isLinux;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://github.com/anthropics/claude-code/releases/download/v${version}/${info.artifact}";
    hash = info.hash;
  };
in
{
  claude = final.stdenv.mkDerivation {
    pname = "claude";
    inherit version src;

    nativeBuildInputs = [ prev.makeWrapper ] ++ prev.lib.optionals is_linux [ prev.autoPatchelfHook ];

    # runtime deps for autoPatchelfHook (linux only)
    buildInputs = prev.lib.optionals is_linux [
      prev.stdenv.cc.cc.lib
      prev.zlib
    ];

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
        --set DISABLE_NON_ESSENTIAL_MODEL_CALLS 1 \
        --set DISABLE_TELEMETRY 1 \
        --set DISABLE_GROWTHBOOK 1 \
        --set DISABLE_ERROR_REPORTING 1 \
        --set DISABLE_BUG_COMMAND 1 \
        --set DISABLE_FEEDBACK_COMMAND 1 \
        --set DISABLE_UPGRADE_COMMAND 1 \
        --set DISABLE_AUTOUPDATER 1 \
        --set DISABLE_UPDATES 1 \
        --set CLAUDE_CODE_ENABLE_TELEMETRY 0 \
        --set CLAUDE_CODE_DISABLE_FEATURE_FLAGS 1 \
        --set CLAUDE_CODE_AUTO_MODE_SERVER 0 \
        --set CLAUDE_CODE_ATTRIBUTION_HEADER 0 \
        --set CLAUDE_CODE_SUPPRESS_SESSION_ATTRIBUTION 1 \
        --set CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY 1 \
        --set CLAUDE_CODE_DISABLE_TERMINAL_TITLE 1 \
        --set CLAUDE_CODE_DISABLE_AWAY_SUMMARY 1 \
        --set CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL 1 \
        --set CLAUDE_CODE_PACKAGE_MANAGER_AUTO_UPDATE 0 \
        --set CLAUDE_CODE_SEND_FEEDBACK 0 \
        --set CLAUDE_CODE_DISABLE_ORG_MEMORY 1 \
        --set BUN_ENABLE_CRASH_REPORTING 0 \
        --set OTEL_SDK_DISABLED true \
        --set OTEL_TRACES_EXPORTER none \
        --set OTEL_METRICS_EXPORTER none \
        --set OTEL_LOGS_EXPORTER none \
        --set DO_NOT_TRACK 1
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

  claude-code = final.claude;
}
