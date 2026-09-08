{
  lib,
  config,
  pkgs,
  ...
}:

with lib;
let
  cfg = config.modules.dev.node;
  nodePkg = cfg.package;
  pnpmPkg = pkgs.pnpm.override { nodejs = nodePkg; };
  expoCliVersion = "57.0.22";
  npmPrefix = "${config.xdg.dataHome}/npm";
  # npm registry tarball ships prebuilt dist/cli.mjs; wrap with our node to avoid global npm install.
  aicommitsPkg = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "aicommits";
    version = "1.11.0";

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/aicommits/-/${pname}-${version}.tgz";
      hash = "sha256-t0zyXrMetwmNAfSCzWSofi9Z1++hH1Jz+7NT816FDF0=";
    };

    sourceRoot = "package";
    dontBuild = true;
    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/share/${pname} $out/bin
      cp -r dist $out/share/${pname}
      makeWrapper ${nodePkg}/bin/node $out/bin/${pname} \
        --add-flags $out/share/${pname}/dist/cli.mjs
      ln -s $out/bin/${pname} $out/bin/aic
      runHook postInstall
    '';

    meta = {
      description = "AI-assisted git commit message generator";
      homepage = "https://github.com/Nutlope/aicommits";
      license = lib.licenses.mit;
      mainProgram = "aicommits";
    };
  };
in
{
  options.modules.dev.node = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable Node.js toolchain";
    };
    package = mkOption {
      type = types.package;
      default = pkgs.nodejs_latest;
      description = "Node.js package to install and use for tooling.";
    };
    installBun = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to install bun alongside Node.js.";
    };
    xdg.enable = mkOption {
      type = types.bool;
      default = true;
      description = "Place npm cache/config under XDG directories.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [
      nodePkg
      pnpmPkg
      # global npm packages
      aicommitsPkg
      pkgs.nodePackages.typescript
      pkgs.nodePackages.eslint
      pkgs.nodePackages.prettier
      pkgs.nodePackages.eas-cli
    ]
    ++ optional cfg.installBun pkgs.bun;
    home.sessionVariables = {
      NPM_CONFIG_USERCONFIG = "${config.xdg.configHome}/npm/config";
      NPM_CONFIG_CACHE = "${config.xdg.cacheHome}/npm";
      NPM_CONFIG_PREFIX = npmPrefix;
      NODE_REPL_HISTORY = "${config.xdg.cacheHome}/node/repl_history";
    };

    # Add npm global bin directory to PATH
    home.sessionPath = [ "${npmPrefix}/bin" ];

    programs.zsh.initContent = lib.mkIf cfg.xdg.enable ''
      export NPM_CONFIG_USERCONFIG="${config.xdg.configHome}/npm/config"
      export NPM_CONFIG_CACHE="${config.xdg.cacheHome}/npm"
      export NPM_CONFIG_PREFIX="${npmPrefix}"
      case ":$PATH:" in
        *":${npmPrefix}/bin:"*) ;;
        *) export PATH="${npmPrefix}/bin:$PATH" ;;
      esac
    '';

    # Ensure tmp dir exists (lightweight) via activation script
    home.activation.ensureNpmTmpDir = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      mkdir -p ${config.xdg.cacheHome}/npm-tmp
    '';

    home.activation.installExpoCli = lib.hm.dag.entryAfter [ "ensureNpmTmpDir" ] ''
      npm_prefix=${lib.escapeShellArg npmPrefix}
      installed_version="$(${nodePkg}/bin/node -e '
        try {
          process.stdout.write(require(process.argv[1]).version);
        } catch (_) {}
      ' "$npm_prefix/lib/node_modules/@expo/cli/package.json" 2>/dev/null || true)"

      if [ "$installed_version" != "${expoCliVersion}" ]; then
        NPM_CONFIG_USERCONFIG=${lib.escapeShellArg "${config.xdg.configHome}/npm/config"} \
          NPM_CONFIG_CACHE=${lib.escapeShellArg "${config.xdg.cacheHome}/npm"} \
          ${nodePkg}/bin/npm install \
            --global \
            --prefix "$npm_prefix" \
            --save-exact \
            --loglevel=error \
            --no-audit \
            --no-fund \
            "@expo/cli@${expoCliVersion}"
      fi
    '';
  };
}
