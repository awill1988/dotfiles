{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.security.audit;

  install_pentest_foss_tools = pkgs.writeShellScriptBin "install-pentest-foss-tools" ''
    set -euo pipefail

    bin_dir="${config.home.homeDirectory}/.local/bin"
    share_dir="${config.xdg.dataHome}/pentest-tools"
    src_dir="$share_dir/src"
    dist_dir="$share_dir/dist"
    npm_prefix="${config.xdg.dataHome}/npm"

    mkdir -p "$bin_dir" "$src_dir" "$dist_dir" "$npm_prefix"

    fetch_latest_asset_url() {
      local repo="$1"
      local asset_regex="$2"

      ${pkgs.curl}/bin/curl -fsSL "https://api.github.com/repos/$repo/releases/latest" \
        | ${pkgs.jq}/bin/jq -r --arg asset_regex "$asset_regex" '
          .assets[]
          | select(.name | test($asset_regex))
          | .browser_download_url
        ' \
        | ${pkgs.coreutils}/bin/head -n 1
    }

    sync_repo() {
      local repo_url="$1"
      local repo_dir="$2"

      if [ -d "$repo_dir/.git" ]; then
        git -C "$repo_dir" pull --ff-only
      else
        git clone --depth 1 "$repo_url" "$repo_dir"
      fi
    }

    install_repo_python_tool() {
      local repo_url="$1"
      local repo_name="$2"
      local entry_script="$3"
      local command_name="$4"
      local repo_dir="$src_dir/$repo_name"
      local venv_dir="$repo_dir/.venv"

      echo "installing $command_name"
      sync_repo "$repo_url" "$repo_dir"

      ${pkgs.python3}/bin/python3 -m venv "$venv_dir"
      "$venv_dir/bin/pip" install --upgrade pip setuptools wheel
      if [ -f "$repo_dir/requirements.txt" ]; then
        "$venv_dir/bin/pip" install -r "$repo_dir/requirements.txt"
      fi

      printf '%s\n' \
        '#!/bin/sh' \
        "exec \"$venv_dir/bin/python\" \"$repo_dir/$entry_script\" \"\$@\"" \
        > "$bin_dir/$command_name"
      chmod 755 "$bin_dir/$command_name"
    }

    install_uv_tool() {
      local package_name="$1"
      local python_version="$2"

      echo "installing $package_name"
      if [ -n "$python_version" ]; then
        ${pkgs.uv}/bin/uv tool install --force --python "$python_version" "$package_name"
      else
        ${pkgs.uv}/bin/uv tool install --force "$package_name"
      fi
    }

    install_npm_tool() {
      local package_name="$1"

      echo "installing $package_name"
      export NPM_CONFIG_USERCONFIG="${config.xdg.configHome}/npm/config"
      export NPM_CONFIG_CACHE="${config.xdg.cacheHome}/npm"
      export NPM_CONFIG_PREFIX="$npm_prefix"
      mkdir -p "$(dirname "$NPM_CONFIG_USERCONFIG")" "$NPM_CONFIG_CACHE" "$NPM_CONFIG_PREFIX"

      ${config.modules.dev.node.package}/bin/npm install -g "$package_name"
    }

    install_uber_apk_signer() {
      local jar_url
      jar_url="$(fetch_latest_asset_url "patrickfav/uber-apk-signer" "uber-apk-signer-.*\\.jar$")"

      echo "installing uber-apk-signer"
      ${pkgs.curl}/bin/curl -fsSL "$jar_url" -o "$dist_dir/uber-apk-signer.jar"

      printf '%s\n' \
        '#!/bin/sh' \
        "exec ${pkgs.jdk}/bin/java -jar \"$dist_dir/uber-apk-signer.jar\" \"\$@\"" \
        > "$bin_dir/uber-apk-signer"
      chmod 755 "$bin_dir/uber-apk-signer"
    }

    install_optool() {
      local zip_url
      local tmp_dir

      zip_url="$(fetch_latest_asset_url "alexzielenski/optool" "optool\\.zip$")"
      tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"

      echo "installing optool"
      ${pkgs.curl}/bin/curl -fsSL "$zip_url" -o "$tmp_dir/optool.zip"
      ${pkgs.unzip}/bin/unzip -oq "$tmp_dir/optool.zip" -d "$tmp_dir"
      install -m 755 "$tmp_dir/optool" "$bin_dir/optool"
    }

    install_dsdump() {
      local repo_dir="$src_dir/dsdump"
      local tmp_dir

      echo "installing dsdump"
      sync_repo "https://github.com/DerekSelander/dsdump.git" "$repo_dir"

      tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"
      ${pkgs.unzip}/bin/unzip -oq "$repo_dir/compiled/dsdump_compiled.zip" -d "$tmp_dir"
      install -m 755 "$tmp_dir/dsdump" "$bin_dir/dsdump"

      printf '%s\n' \
        '#!/bin/sh' \
        "exec \"$bin_dir/dsdump\" \"\$@\"" \
        > "$bin_dir/class-dump"
      chmod 755 "$bin_dir/class-dump"
    }

    install_zap() {
      local zip_url
      local tmp_dir
      local zap_root

      zip_url="$(fetch_latest_asset_url "zaproxy/zaproxy" "ZAP_.*_Crossplatform\\.zip$")"
      tmp_dir="$(${pkgs.coreutils}/bin/mktemp -d)"

      echo "installing owasp zap"
      ${pkgs.curl}/bin/curl -fsSL "$zip_url" -o "$tmp_dir/zap.zip"
      ${pkgs.unzip}/bin/unzip -oq "$tmp_dir/zap.zip" -d "$dist_dir"
      zap_root="$(${pkgs.findutils}/bin/find "$dist_dir" -maxdepth 1 -type d -name 'ZAP_*' | ${pkgs.coreutils}/bin/head -n 1)"

      printf '%s\n' \
        '#!/bin/sh' \
        "cd \"$zap_root\"" \
        'exec ./zap.sh "$@"' \
        > "$bin_dir/zap.sh"
      chmod 755 "$bin_dir/zap.sh"

      printf '%s\n' \
        '#!/bin/sh' \
        "exec \"$bin_dir/zap.sh\" \"\$@\"" \
        > "$bin_dir/zaproxy"
      chmod 755 "$bin_dir/zaproxy"
    }

    install_uv_tool "frida-tools" "3.11"
    install_uv_tool "objection" "3.11"
    install_uv_tool "drozer" "3.11"
    install_uv_tool "mobsf" "3.11"
    install_npm_tool "apk-mitm"
    install_repo_python_tool "https://github.com/ticarpi/jwt_tool.git" "jwt_tool" "jwt_tool.py" "jwt_tool"
    install_repo_python_tool "https://github.com/AloneMonkey/frida-ios-dump.git" "frida-ios-dump" "dump.py" "frida-ios-dump"
    install_uber_apk_signer
    install_optool
    install_dsdump
    install_zap
  '';
in
{
  options.modules.security.audit = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security vulnerability scanning, auditing, and reverse engineering tools.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      python3Packages.checkdmarc
      gitleaks
      grype
      mitmproxy
      nikto
      nuclei
      radare2
      semgrep
      testssl
      trivy
      trufflehog
      nmap
      mtkclient
      apksigner
      ghidra
      install_pentest_foss_tools
    ];
  };
}
