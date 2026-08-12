{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (config.home) user-info;
  enableSigning =
    !builtins.isNull user-info.git.signingKey && !builtins.isNull user-info.git.signingFormat;
  useSsh = user-info.git.signingFormat == "ssh";

  ssh-keygen = "${pkgs.openssh}/bin/ssh-keygen";
  ssh-add = "${pkgs.openssh}/bin/ssh-add";

  # wrapper that auto-detects yubikey vs file-based ssh key at sign time
  git-ssh-sign = pkgs.writeShellScriptBin "git-ssh-sign" ''
    set -euo pipefail

    # for non-sign operations, pass through directly to ssh-keygen
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

    # detect yubikey-derived ssh key from gpg-agent
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
      # write agent pubkey to a temp file for ssh-keygen -f
      tmp_pubkey="$(mktemp /tmp/git-ssh-sign-XXXXXX.pub)"
      echo "$yubikey_line" > "$tmp_pubkey"
      sign_key="$tmp_pubkey"
    else
      # fallback to file-based keys
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

    # rebuild args, replacing the -f <key> value with the detected key
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
in
{
  programs.git = {
    enable = true;
    package = pkgs.git;
    signing =
      if enableSigning then
        {
          key =
            if useSsh then
              "~/.ssh/id_ed25519.pub" # placeholder; wrapper overrides at runtime
            else
              user-info.git.signingKey; # gpg key id for openpgp format
          signByDefault = true;
          format = user-info.git.signingFormat;
        }
      else
        { };
    settings = {
      user = {
        name = user-info.fullName;
      };
      core = {
        editor = "${pkgs.vim}/bin/vim";
        trustctime = false;
        logAllRefUpdates = true;
        precomposeunicode = true;
        whitespace = "trailing-space,space-before-tab";
      };
      alias =
        let
          # run aicommits, then amend to lowercase the full message
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
      github.user = user-info.git.github;
    }
    // lib.optionalAttrs (enableSigning && useSsh) {
      gpg.ssh = {
        program = "${git-ssh-sign}/bin/git-ssh-sign";
        allowedSignersFile = "${config.xdg.configHome}/git/allowed_signers";
      };
    }
    // {
      "includeIf \"gitdir:~/projects/\"" = {
        path = "${config.xdg.configHome}/git/personal.gitconfig";
      };
      "includeIf \"gitdir:~/projects/arro/\"" = {
        path = "${config.xdg.configHome}/git/arro.gitconfig";
      };
    };
  };

  # generate allowed_signers from gpg public keyring + file-based ssh key
  home.activation.generate-allowed-signers = lib.mkIf (enableSigning && useSsh) (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                allowed_signers_file="${config.xdg.configHome}/git/allowed_signers"
                mkdir -p "$(dirname "$allowed_signers_file")"

                signers=""

                # yubikey ssh pubkey from gpg public keyring (no card needed)
                gpg_ssh_key="$(${pkgs.gnupg}/bin/gpg --export-ssh-key "${user-info.git.signingKey}" 2>/dev/null || true)"
                if [ -n "$gpg_ssh_key" ]; then
                  signers="''${signers}${user-info.git.email} $gpg_ssh_key
      "
                  signers="''${signers}${user-info.git.emailSecondary} $gpg_ssh_key
      "
                fi

                # file-based ed25519 fallback
                if [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
                  file_key="$(cat "$HOME/.ssh/id_ed25519.pub")"
                  signers="''${signers}${user-info.git.email} $file_key
      "
                  signers="''${signers}${user-info.git.emailSecondary} $file_key
      "
                fi

                if [ -n "$signers" ]; then
                  printf '%s' "$signers" > "$allowed_signers_file"
                else
                  echo "warning: no ssh keys found for allowed_signers" >&2
                  : > "$allowed_signers_file"
                fi
    ''
  );
}
