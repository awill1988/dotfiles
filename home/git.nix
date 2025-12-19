{ config, pkgs, lib, ... }:
let
  inherit (config.home) user-info;
  enableSigning = !builtins.isNull user-info.git.signingKey && !builtins.isNull user-info.git.signingFormat;
in {
  programs.git = {
    enable = true;
    package = pkgs.git;
    # iniContent.gpg.program = lib.mkForce "gpg"; # enables signing from wsl
    signing = if enableSigning then {
      key = user-info.git.signingKey;
      signByDefault = true;
      format = user-info.git.signingFormat;
    } else {};
    settings = {
      user = { name = user-info.fullName; };
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
          aicommits_lowercase = ''
            !sh -c 'aicommits --type conventional "$@" && git log -1 --format=%B HEAD | tr "[:upper:]" "[:lower:]" | git commit --amend --no-edit -F -' -'';
        in
        { ccommit = aicommits_lowercase; };
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
      pull.rebase = true;
      push.default = "tracking";
      rebase.autosquash = true;
      rerere.enabled = true;
      status.submoduleSummary = true;
      github.user = user-info.git.github;
    } // {
      "includeIf \"gitdir:~/projects/\"" = {
        path = "${config.xdg.configHome}/git/personal.gitconfig";
      };
    };
  };
}
