{ config, pkgs, lib, ... }:
let inherit (config.home) user-info;
in {
  programs.git = {
    enable = true;
    package = pkgs.git;
    # iniContent.gpg.program = lib.mkForce "gpg"; # enables signing from wsl
    settings = {
      user = { name = user-info.fullName; };
      gpg.format = "openpgp";
      user.signingKey = user-info.gpg.masterKey;
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
      commit.gpgsign = true;
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
    };
  };

  # SSH allowed signers file for commit signature verification
  home.file.".ssh/allowed_signers" = {
    text =
      "adam@williams.engineer ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDs9Z0O5aU1LnZ5MXV+TSvnFxzjuyFsrNOAMgGy/B+gES+H5gtXyEWCrxl66cD51B9upZ7W/oFoCDPcHccuX3qn+ON32zqZP9+1sKAgM8ze0TRvBaV8DRgHVJk5OFHjYmZ9p/ee4HlVmE5AnbujN2QWCmN3SJmPh6lKnp01vrDjUQy2NsTvxRs26iiKqzrMXS8Rv9ESAUGhttF9H7kuUra7t2TwznmjxTXWr4dSCwkZwIVyhJM9LcDw/m5Rjl74aiwZ5R8D9zYBUbUeNSAoUZVgfH42uAokXoNSeGos8EHmH7b9k3JLVMghFFymdTZrPowApfN31fEMLD7Ad+pnBfFsZWpVoUgAsiyPCMgR99eQgQhHOGVMRK0mag0m9kR98+l2EXWnyxB2Ht+esH5JWnxcma/UWaeFwgwyKwhprXsh/OS7JSJkAytiYiZfCzoCAiJLkcj6ldR4mizAsV/T3QxxZknkH771ufILdWPkMGcRLndKxN/90hx56e2yBub2+bE42IZAw4h5VULKHpcu7f2d/PoqJQ//F3v68YqlJP4p2wMWP0+6bAqNZY2b95foqFui7s8JHGpY5UmHMUqtnPYx2XXqStxiGpmCGw9G/ZZoXm97LvOqXwpxg+x62wmpdXLJ0t48+t/f5BSvPYrHeiR42RnxHzeznYgiNNYsJfwrrw== cardno:31_367_676";
    recursive = false;
    executable = false;
  };
}
