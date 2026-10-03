{
  config,
  pkgs,
  lib,
  ...
}:
with lib;
let
  cfg = config.modules.vcs.git;
  resolvedProfiles = config.developer.resolvedProfiles;
  resolvedProfilesList = attrValues resolvedProfiles;
  primaries = filter (p: p.isPrimary) resolvedProfilesList;
  primaryProfile =
    if primaries != [ ] then
      head primaries
    else if resolvedProfilesList != [ ] then
      head resolvedProfilesList
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
    prev_arg=""
    orig_key=""
    skip_next=false

    for arg in "$@"; do
      if [ "$arg" = "sign" ] && [ "$prev_arg" = "-Y" ]; then
        is_sign=true
      fi
      if [ "$skip_next" = "true" ]; then
        orig_key="$arg"
        skip_next=false
      fi
      if [ "$arg" = "-f" ]; then
        skip_next=true
      fi
      prev_arg="$arg"
    done

    if [ "$is_sign" = "false" ]; then
      exec ${ssh-keygen} "$@"
    fi

    sign_key=""
    tmp_pubkey=""
    cleanup() {
      [ -n "$tmp_pubkey" ] && rm -f "$tmp_pubkey"
    }
    trap cleanup EXIT

    agent_keys="$(${ssh-add} -L 2>/dev/null || true)"

    # Tier 1: Check Yubikey / GPG key in active SSH agent
    if [ -n "$orig_key" ] && [ ! -f "$orig_key" ]; then
      gpg_key="$(${pkgs.gnupg}/bin/gpg --export-ssh-key "$orig_key" 2>/dev/null || true)"
      if [ -n "$gpg_key" ]; then
        gpg_key_body="$(echo "$gpg_key" | awk '{print $2}')"
        if [ -n "$gpg_key_body" ] && echo "$agent_keys" | grep -q "$gpg_key_body"; then
          tmp_pubkey="$(mktemp /tmp/git-ssh-sign-XXXXXX.pub)"
          echo "$gpg_key" > "$tmp_pubkey"
          sign_key="$tmp_pubkey"
        fi
      fi
    fi

    if [ -z "$sign_key" ] && [ -n "$agent_keys" ]; then
      yubikey_line="$(echo "$agent_keys" | grep -E 'openpgp:|cardno:' | head -n1 || true)"
      if [ -n "$yubikey_line" ]; then
        tmp_pubkey="$(mktemp /tmp/git-ssh-sign-XXXXXX.pub)"
        echo "$yubikey_line" > "$tmp_pubkey"
        sign_key="$tmp_pubkey"
      fi
    fi

    if [ -z "$sign_key" ] && [ -n "$orig_key" ] && [ -f "$orig_key" ]; then
      orig_key_body="$(awk '{print $2}' "$orig_key" 2>/dev/null || true)"
      if [ -n "$orig_key_body" ] && echo "$agent_keys" | grep -q "$orig_key_body"; then
        sign_key="$orig_key"
      fi
    fi

    # Tier 2: Fallback to local SSH key file (~/.ssh/id_ed25519.pub)
    if [ -z "$sign_key" ]; then
      for candidate in "$HOME/.ssh/id_ed25519.pub" "$HOME/.ssh/id_rsa.pub"; do
        if [ -f "$candidate" ]; then
          sign_key="$candidate"
          break
        fi
      done
    fi

    # Tier 3: Fail if no key found
    if [ -z "$sign_key" ]; then
      echo "error: no ssh signing key available (Yubikey not connected and ~/.ssh/id_ed25519.pub missing)" >&2
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

  pre-push-hook = pkgs.writeShellScript "git-pre-push" ''
    set -euo pipefail

    remote_name="''${1:-}"
    remote_url="''${2:-}"
    zero="0000000000000000000000000000000000000000"

    stdin_data="$(${pkgs.coreutils}/bin/cat)"
    if [ -z "$stdin_data" ]; then
      exit 0
    fi

    while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
      [ -z "$local_ref" ] && continue

      # Branch or ref deletion
      if [ "$local_sha" = "$zero" ]; then
        continue
      fi

      if [ "$remote_sha" = "$zero" ]; then
        if [ -n "$remote_name" ] && ${pkgs.git}/bin/git for-each-ref --format='%(refname)' "refs/remotes/$remote_name" 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q .; then
          commits="$(${pkgs.git}/bin/git rev-list "$local_sha" --not --remotes="$remote_name")"
        elif ${pkgs.git}/bin/git for-each-ref --format='%(refname)' refs/remotes/ 2>/dev/null | ${pkgs.gnugrep}/bin/grep -q .; then
          commits="$(${pkgs.git}/bin/git rev-list "$local_sha" --not --remotes)"
        else
          commits="$(${pkgs.git}/bin/git rev-list "$local_sha")"
        fi
      else
        commits="$(${pkgs.git}/bin/git rev-list "$remote_sha..$local_sha")"
      fi

      for commit in $commits; do
        sig_status="$(${pkgs.git}/bin/git log -1 --format='%G?' "$commit" 2>/dev/null || echo "N")"
        case "$sig_status" in
          G|U)
            ;;
          *)
            echo "error: push rejected: commit $commit is not cryptographically signed (signature status: $sig_status)" >&2
            echo "commit details: $(${pkgs.git}/bin/git log -1 --format='%h - %an: %s' "$commit" 2>/dev/null)" >&2
            echo "all commits must be cryptographically signed with a valid SSH or GPG key before pushing." >&2
            exit 1
            ;;
        esac
      done
    done <<< "$stdin_data"

    git_dir="$(${pkgs.git}/bin/git rev-parse --git-dir 2>/dev/null || true)"
    if [ -n "$git_dir" ] && [ -f "$git_dir/hooks/pre-push" ] && [ -x "$git_dir/hooks/pre-push" ]; then
      current_script="$(${pkgs.coreutils}/bin/realpath "$0")"
      local_hook="$(${pkgs.coreutils}/bin/realpath "$git_dir/hooks/pre-push")"
      if [ "$current_script" != "$local_hook" ]; then
        printf '%s\n' "$stdin_data" | "$git_dir/hooks/pre-push" "$remote_name" "$remote_url"
      fi
    fi

    exit 0
  '';

  post-checkout-hook = pkgs.writeShellScript "git-post-checkout" ''
    set -euo pipefail

    prev_head="''${1:-}"
    new_head="''${2:-}"
    is_branch_checkout="''${3:-0}"

    if [ "$is_branch_checkout" -ne 1 ]; then
      exit 0
    fi

    branch="$(${pkgs.git}/bin/git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [ -n "$branch" ]; then
      upstream="$(${pkgs.git}/bin/git rev-parse --symbolic-full-name --abbrev-ref '@{u}' 2>/dev/null || true)"
      if [ -z "$upstream" ]; then
        preferred_remote="$(${pkgs.git}/bin/git config checkout.defaultRemote 2>/dev/null || echo "origin")"
        if ${pkgs.git}/bin/git rev-parse --verify --quiet "refs/remotes/$preferred_remote/$branch" >/dev/null 2>&1; then
          ${pkgs.git}/bin/git branch --set-upstream-to="$preferred_remote/$branch" "$branch" >/dev/null 2>&1 || true
        fi
      fi
    fi

    git_dir="$(${pkgs.git}/bin/git rev-parse --git-dir 2>/dev/null || true)"
    if [ -n "$git_dir" ] && [ -f "$git_dir/hooks/post-checkout" ] && [ -x "$git_dir/hooks/post-checkout" ]; then
      current_script="$(${pkgs.coreutils}/bin/realpath "$0")"
      local_hook="$(${pkgs.coreutils}/bin/realpath "$git_dir/hooks/post-checkout")"
      if [ "$current_script" != "$local_hook" ]; then
        exec "$git_dir/hooks/post-checkout" "$@"
      fi
    fi

    exit 0
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
    ) resolvedProfilesList
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
          hooksPath = "${config.xdg.configHome}/git/hooks";
        };
        alias =
          let
            aicommits_lowercase = ''!sh -c 'aicommits --type conventional "$@" && git log -1 --format=%B HEAD | tr "[:upper:]" "[:lower:]" | git commit --amend --no-edit -F -' -'';
          in
          {
            ccommit = aicommits_lowercase;
          };
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
        checkout.defaultRemote = "origin";
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
        ".worktrees/"
        "worktrees/"
        ".worktree/"
        "worktree/"
        ".wt/"
        "*.worktree/"
        ".*-wt*/"
        ".claude-wt-*/"
        ".agent-worktrees/"
        "agent-worktrees/"
        ".agent-scratch/"
        ".agent-temp/"
        "agent-scratch/"
        ".claude/"
        ".claude.json"
        ".claude.settings.json"
        ".claude_history"
        ".claude_session*"
        ".gemini/"
        ".gemini.json"
        ".antigravity/"
        ".antigravitycli/"
        ".antigravity_history"
        ".agy/"
        ".agy_history"
        ".codex/"
        ".codex.json"
        ".opencode/"
        ".opencode.json"
        ".cursor/"
        ".windsurf/"
        ".copilot/"
        ".aider*"
        ".derived_data/"
        "*.mp4"
      ];
    };

    xdg.configFile."git/hooks/pre-push" = {
      source = pre-push-hook;
      executable = true;
    };

    xdg.configFile."git/hooks/post-checkout" = {
      source = post-checkout-hook;
      executable = true;
    };

    home.packages = with pkgs; [
      git-ssh-sign
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
        '') resolvedProfilesList}

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
