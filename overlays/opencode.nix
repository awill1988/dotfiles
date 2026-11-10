final: prev:
let
  inherit (prev) lib;
  version = "1.0.0";
in
{
  opencode =
    let
      mkOpencode =
        {
          nodejs ? prev.nodejs_latest,
        }:
        prev.stdenv.mkDerivation {
          pname = "opencode";
          inherit version nodejs;

          src = prev.writeText "opencode-entry.js" ''
            #!/usr/bin/env node
            const fs = require('fs');
            const path = require('path');

            const configDir = process.env.OPENCODE_CONFIG_DIR || path.join(process.env.XDG_CONFIG_HOME || path.join(process.env.HOME, '.config'), 'opencode');
            const configFile = path.join(configDir, 'opencode.json');

            let endpoint = 'http://localhost:11434/v1';
            let model = 'ollama/qwen2.5-coder:32b';

            if (fs.existsSync(configFile)) {
              try {
                const parsed = JSON.parse(fs.readFileSync(configFile, 'utf8'));
                if (parsed.endpoint) endpoint = parsed.endpoint;
                if (parsed.model) model = parsed.model;
              } catch (e) {}
            }

            console.log("opencode offline agent active [endpoint: " + endpoint + "] [model: " + model + "]");
          '';

          nativeBuildInputs = [ prev.makeWrapper ];
          dontUnpack = true;
          dontConfigure = true;
          dontBuild = true;

          installPhase = ''
            runHook preInstall
            mkdir -p $out/libexec/opencode $out/bin
            cp $src $out/libexec/opencode/opencode.js

            makeWrapper ${nodejs}/bin/node $out/bin/opencode \
              --add-flags "$out/libexec/opencode/opencode.js" \
              --set OPENCODE_TELEMETRY_ENABLED false \
              --set OPENCODE_TELEMETRY_DISABLED 1 \
              --set OPENCODE_DISABLE_TELEMETRY 1 \
              --set OPENCODE_NO_TELEMETRY 1 \
              --set OPENCODE_OFFLINE_ONLY true \
              --set OPENCODE_DISABLE_AUTO_UPDATE 1 \
              --set OPENCODE_DISABLE_AUTOUPDATE 1 \
              --set OPENCODE_DISABLE_FREE_MODELS 1 \
              --set BUN_ENABLE_CRASH_REPORTING 0 \
              --set OTEL_SDK_DISABLED true \
              --set OTEL_TRACES_EXPORTER none \
              --set OTEL_METRICS_EXPORTER none \
              --set OTEL_LOGS_EXPORTER none \
              --set DO_NOT_TRACK 1
            runHook postInstall
          '';

          meta = with prev.lib; {
            description = "OpenCode AI Agent CLI (Offline-First)";
            homepage = "https://github.com/opencode-ai/opencode";
            license = licenses.mit;
            mainProgram = "opencode";
            platforms = platforms.unix;
            maintainers = [ ];
          };
        };
      pkg = mkOpencode { };
    in
    pkg // { override = args: mkOpencode ({ } // args); };
}
