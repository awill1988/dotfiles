final: prev:
let
  version = "0.27.3";
  src = prev.fetchurl {
    url = "https://github.com/google-gemini/gemini-cli/releases/download/v${version}/gemini.js";
    hash = "sha256-I1B1RyImSBRrrF6cFzHv5kOR1R5K6tlFZbKF/Jn1ff4=";
  };
  nodejs = prev.nodejs_latest;
in
{
  gemini =
    let
      mkGemini =
        {
          nodejs ? prev.nodejs_latest,
        }:
        prev.stdenv.mkDerivation {
          pname = "gemini";
          inherit version src nodejs;

          nativeBuildInputs = [ prev.makeWrapper ];
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out/libexec/gemini $out/bin
            cp ${src} $out/libexec/gemini/gemini.js

            makeWrapper ${nodejs}/bin/node $out/bin/gemini \
              --add-flags "$out/libexec/gemini/gemini.js" \
              --set GEMINI_CLI_TELEMETRY_ENABLED false
            runHook postInstall
          '';

          meta = with prev.lib; {
            description = "Gemini CLI (release bundle)";
            homepage = "https://github.com/google-gemini/gemini-cli";
            license = licenses.asl20;
            mainProgram = "gemini";
            platforms = platforms.unix;
            maintainers = [ ];
          };
        };
      pkg = mkGemini { };
    in
    pkg
    // {
      override = args: mkGemini ({ } // args);
    };
}
