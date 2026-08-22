{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.languages.ruby;
in
{
  options.modules.languages.ruby = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Ruby, rbenv, solargraph, and jekyll.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      rbenv
      ruby
      jekyll
      rubyPackages.solargraph
    ];
  };
}
