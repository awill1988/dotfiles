{ config, pkgs, lib, ... }:
let inherit (config.home) user-info;

in {
  programs.git = {
    enable = true;
    package = pkgs.git;
    userName = user-info.fullName;
    extraConfig = {
      core = {
        editor = "${pkgs.vim}/bin/vim";
        trustctime = false;
        logAllRefUpdates = true;
        precomposeunicode = true;
        whitespace = "trailing-space,space-before-tab";
      };
      branch.autosetupmerge = true;
      color.ui = "auto";
      commit.verbose = true;
      diff.submodule = "log";
      diff.tool = "${pkgs.vim}/bin/vimdiff";
      difftool.prompt = false;
      http.sslCAinfo = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      http.sslverify = true;
      hub.protocol = "${pkgs.openssh}/bin/ssh";
      merge.tool = "${pkgs.vim}/bin/vimdiff";
      mergetool.keepBackup = true;
      pull.rebase = true;
      push.default = "tracking";
      rebase.autosquash = true;
      rerere.enabled = true;
      status.submoduleSummary = true;
      github.user = user-info.github;
    };
  };
}
