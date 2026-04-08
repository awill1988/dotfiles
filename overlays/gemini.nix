final: prev:
let
  version = "0.36.0";
  src = prev.fetchzip {
    url = "https://github.com/google-gemini/gemini-cli/releases/download/v${version}/gemini-cli-bundle.zip";
    hash = "sha256-wu+QZ5roBNY1mwtte+7opKFBRdOCXONW95UEJ7M3gJI=";
    stripRoot = false;
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
          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out/libexec/gemini $out/bin
            cp -r . $out/libexec/gemini/

            makeWrapper ${nodejs}/bin/node $out/bin/gemini \
              --add-flags "$out/libexec/gemini/gemini.js" \
              --set GEMINI_TELEMETRY_ENABLED false
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
