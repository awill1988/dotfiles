{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.vcs.git;
  profilesList = attrValues config.developer.profiles;
  primaries = filter (p: p.isPrimary) profilesList;
  primaryProfile =
    if primaries != [ ] then
      head primaries
    else if profilesList != [ ] then
      head profilesList
    else
      null;

  enableSigning =
    primaryProfile != null
    && !builtins.isNull primaryProfile.identity.signingKey
    && !builtins.isNull primaryProfile.identity.signingFormat;
  useSsh = primaryProfile != null && primaryProfile.identity.signingFormat == "ssh";

  ssh-keygen = "${pkgs.openssh}/bin/ssh-keygen";
  ssh-add = "${pkgs.openssh}/bin/ssh-add";

  git-ssh-sign = pkgs.writeShellScriptBin "git-ssh-sign" ''
    set -euo pipefail

    is_sign=false
    for arg in "$@"; do
      if [ "$arg" = "sign" ] && [ "$prev_arg" = "-Y" ]; then
        is_sign=true
        break
      fi
      prev_arg="$arg"
    done

    if [ "$is_sign" = "false" ]; then
      exec ${ssh-keygen} "$@"
    fi

    yubikey_line=""
    if agent_keys="$(${ssh-add} -L 2>/dev/null)"; then
      yubikey_line="$(echo "$agent_keys" | grep -E 'openpgp:|cardno:' | head -n1 || true)"
    fi

    sign_key=""
    tmp_pubkey=""
    cleanup() {
      [ -n "$tmp_pubkey" ] && rm -f "$tmp_pubkey"
    }
    trap cleanup EXIT

    if [ -n "$yubikey_line" ]; then
      tmp_pubkey="$(mktemp /tmp/git-ssh-sign-XXXXXX.pub)"
      echo "$yubikey_line" > "$tmp_pubkey"
      sign_key="$tmp_pubkey"
    else
      for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
        if [ -f "$candidate" ]; then
          sign_key="$candidate"
          break
        fi
      done
    fi

    if [ -z "$sign_key" ]; then
      echo "error: no ssh signing key found (no yubikey, no ~/.ssh/id_ed25519.pub)" >&2
      exit 1
    fi

    new_args=()
    skip_next=false
    for arg in "$@"; do
      if [ "$skip_next" = "true" ]; then
        skip_next=false
        new_args+=("$sign_key")
        continue
      fi
      if [ "$arg" = "-f" ]; then
        skip_next=true
      fi
      new_args+=("$arg")
    done

    exec ${ssh-keygen} "''${new_args[@]}"
  '';

  gitIncludeIfs = listToAttrs (
    concatMap (
      p:
      map (prefix: {
        name = "includeIf \"gitdir:${prefix}/\"";
        value = {
          path = "${config.xdg.configHome}/profiles/${p.name}/git/config";
        };
      }) p.pathPrefixes
    ) profilesList
  );
in
{
  options.modules.vcs.git = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Git configuration, signing wrappers, profile auto-routing, and GitHub CLI tools.";
    };
  };

  config = mkIf cfg.enable {
    programs.git = {
      enable = true;
      package = pkgs.git;
      signing =
        if enableSigning then
          {
            key = if useSsh then "~/.ssh/id_ed25519.pub" else primaryProfile.identity.signingKey;
            signByDefault = true;
            format = primaryProfile.identity.signingFormat;
          }
        else
          { };
      settings = {
        core = {
          editor = "${pkgs.vim}/bin/vim";
          trustctime = false;
          logAllRefUpdates = true;
          precomposeunicode = true;
          whitespace = "trailing-space,space-before-tab";
        };
        alias =
          let
            aicommits_lowercase = ''!sh -c 'aicommits --type conventional "$@" && git log -1 --format=%B HEAD | tr "[:upper:]" "[:lower:]" | git commit --amend --no-edit -F -' -'';
          in
          {
            ccommit = aicommits_lowercase;
          };
        branch.autosetupmerge = true;
        color.ui = "auto";
        commit.verbose = true;
        diff.submodule = "log";
        diff.tool = "${pkgs.vim}/bin/vimdiff";
        difftool.prompt = false;
        http.sslCAinfo = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        http.sslverify = true;
        hub.protocol = "ssh";
        merge.tool = "${pkgs.vim}/bin/vimdiff";
        mergetool.keepBackup = true;
        branch.autoSetupMerge = "simple";
        pull.rebase = true;
        push.autoSetupRemote = true;
        push.default = "simple";
        rebase.autosquash = true;
        rerere.enabled = true;
        status.submoduleSummary = true;
      }
      // optionalAttrs (primaryProfile != null) {
        user =
          optionalAttrs (primaryProfile.identity.fullName != null) {
            name = primaryProfile.identity.fullName;
          }
          // optionalAttrs (primaryProfile.identity.email != null) {
            email = primaryProfile.identity.email;
          };
      }
      // optionalAttrs (primaryProfile != null && primaryProfile.identity.github != null) {
        github.user = primaryProfile.identity.github;
      }
      // optionalAttrs (enableSigning && useSsh) {
        gpg.ssh = {
          program = "${git-ssh-sign}/bin/git-ssh-sign";
          allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";
        };
      }
      // gitIncludeIfs;

      ignores = [
        "[._]*.s[a-v][a-z]"
        "[._]*.sw[a-p]"
        "[._]s[a-rt-v][a-z]"
        "[._]ss[a-gi-z]"
        "Session.vim"
        "Sessionx.vim"
        ".netrwhist"
        "[._]*.un~"
        "*~"
        "*.bak"
        "*.tmp"
        "*.temp"
        ".#*"
        "#*#"
        "*.dmp"
        "*.stackdump"
        "*.pcap"
        "*.pcapng"
        "tags"
        ".DS_Store"
        ".AppleDouble"
        ".LSOverride"
        "Icon"
        "Icon\r"
        "._*"
        ".DocumentRevisions-V100"
        ".fseventsd"
        ".Spotlight-V100"
        ".TemporaryItems"
        ".Trashes"
        ".VolumeIcon.icns"
        ".com.apple.timemachine.donotpresent"
        ".AppleDB"
        ".AppleDesktop"
        "Network Trash Folder"
        "Temporary Items"
        ".apdisk"
        "__MACOSX/"
        ".localized"
        ".Trash-*"
        ".fuse_hidden*"
        ".nfs*"
        "lost+found"
        ".directory"
        "Thumbs.db"
        "ehthumbs.db"
        "ehthumbs_vista.db"
        "Desktop.ini"
        "IconCache.db"
        "$RECYCLE.BIN/"
        "System Volume Information/"
        "*.lnk"
        "*.url"
        "DerivedData/"
        "build/"
        "*.xcuserstate"
        "*.xccheckout"
        "*.xcscmblueprint"
        "*.moved-aside"
        "*.pbxuser"
        "*.mode1v3"
        "*.mode2v3"
        "*.perspectivev3"
        "xcuserdata/"
        "*.ipa"
        "*.dSYM"
        "*.dSYM.zip"
        ".build/"
        ".swiftpm/"
        "Pods/"
        "Carthage/Build/"
        "*.xcframework"
        "*.swiftmodule"
        ".direnv/"
        ".claude/"
        ".claude.json"
        ".claude.settings.json"
        ".gemini/"
        ".gemini.json"
        ".codex/"
        ".codex.json"
        ".aider*"
        ".cursor/"
        ".windsurf/"
        ".antigravitycli/"
        "*.mp4"
      ];
    };

    home.packages = with pkgs; [
      gh
      act
      maestro
    ];

    home.activation.generate-allowed-signers = mkIf (enableSigning && useSsh) (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        allowed_signers_file="${config.xdg.configHome}/git/allowed_signers"
        mkdir -p "$(dirname "$allowed_signers_file")"
        signers=""

        ${concatMapStringsSep "\n" (p: ''
          if [ -n "${toString p.identity.signingKey}" ]; then
            gpg_ssh_key="$(${pkgs.gnupg}/bin/gpg --export-ssh-key "${p.identity.signingKey}" 2>/dev/null || true)"
            if [ -n "$gpg_ssh_key" ]; then
              signers="''${signers}${p.identity.email} $gpg_ssh_key
            "
            fi
          fi
          if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
            file_key="$(cat "$HOME/.ssh/id_ed25519.pub")"
            signers="''${signers}${p.identity.email} $file_key
          "
          fi
        '') profilesList}

        if [ -n "$signers" ]; then
          printf '%s' "$signers" > "$allowed_signers_file"
        else
          echo "warning: no ssh keys found for allowed_signers" >&2
          : > "$allowed_signers_file"
        fi
      ''
    );
  };
}
