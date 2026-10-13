{ pkgs }:
let
  module = import ./default.nix {
    inherit pkgs;
    inherit (pkgs) lib;
    config.modules.vcs.git.enable = true;
  };
  hook = module.config.content.xdg.configFile."git/hooks/pre-push".source;
in
pkgs.runCommand "git-signing-contracts"
  {
    nativeBuildInputs = [ pkgs.python3 pkgs.git pkgs.openssh ];
    PRE_PUSH_HOOK = hook;
  }
  ''
    python3 ${./test_pre_push.py}
    touch "$out"
  ''
