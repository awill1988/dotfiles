final: prev:
let
  version = "2.1.5";
  src = prev.fetchurl {
    url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
    hash = "sha256-pJWGkKtGn8DIMuHc+LxhS0ta4nxrZyKJOd0qXfAM7VI=";
  };

  mkClaude = { nodejs ? prev.nodejs_latest }: prev.stdenv.mkDerivation {
    pname = "claude";
    inherit version src nodejs;

    nativeBuildInputs = [ prev.makeWrapper ];
    buildInputs = [ nodejs ];

    dontConfigure = true;
    dontBuild = true;
    installPhase = ''
      runHook preInstall

      mkdir -p $out/libexec/claude $out/bin
      cp -r . $out/libexec/claude

      makeWrapper ${nodejs}/bin/node $out/bin/claude \
        --set DISABLE_AUTOUPDATER 1 \
        --unset DEV \
        --set CLAUDE_CODE_TELEMETRY_DISABLED 1 \
        --set CLAUDE_CODE_DISABLE_FEEDBACK 1 \
        --set STATSIG_LOCAL_MODE true \
        --set STATSIG_ENVIRONMENT dev \
        --add-flags "$out/libexec/claude/cli.js"

      runHook postInstall
    '';

    meta = with prev.lib; {
      description = "Claude Code CLI";
      homepage = "https://github.com/anthropics/claude-code";
      license = licenses.unfree;
      mainProgram = "claude";
      platforms = platforms.unix;
      maintainers = [ ];
    };
  };
in
{
  claude =
    let pkg = mkClaude { };
    in pkg // {
      override = args: mkClaude ({ } // args);
    };
}
