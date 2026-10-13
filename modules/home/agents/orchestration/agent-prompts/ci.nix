let
  lock = builtins.fromJSON (builtins.readFile ../../../../../flake.lock);
  fetch_input = name: builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.${name}}.locked;
  pkgs = import (fetch_input "nixpkgs") { system = builtins.currentSystem; };
in
pkgs.linkFarm "prompt-cutover-contracts" {
  prompts = import ./check.nix {
    inherit pkgs;
    prompts_src = fetch_input "prompts";
  };
  git-signing = import ../../../vcs/git/check.nix { inherit pkgs; };
}
