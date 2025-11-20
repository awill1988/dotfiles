{ config, pkgs, lib, ... }:
let inherit (config.home) user-info;
in {
  programs.git = {
    enable = true;
    package = pkgs.git;
    userName = user-info.fullName;
    # iniContent.gpg.program = lib.mkForce "gpg"; # enables signing from wsl
    extraConfig = {
      user.signingkey = "${config.home.homeDirectory}/.ssh/id_ed25519.pub";
      gpg.format = "ssh";
      core = {
        editor = "${pkgs.vim}/bin/vim";
        trustctime = false;
        logAllRefUpdates = true;
        precomposeunicode = true;
        whitespace = "trailing-space,space-before-tab";
        sshCommand = "ssh"; # enables ssh from wsl
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
      pull.rebase = true;
      push.default = "tracking";
      rebase.autosquash = true;
      rerere.enabled = true;
      status.submoduleSummary = true;
      github.user = user-info.github;
    } // {
      "includeIf \"gitdir:~/projects/\"" = {
        path = "${config.xdg.configHome}/git/personal.gitconfig";
      };
      "includeIf \"gitdir:~/projects/onXmaps/\"" = {
        path = "${config.xdg.configHome}/git/work.gitconfig";
      };
    };
  };
}
