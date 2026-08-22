{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.languages.elixir;

  install-elixir-escripts = pkgs.writeScriptBin "install-elixir-escripts" ''
    #!/bin/sh
    mix local.hex --force
    mix local.rebar --force
    mix escript.install --force hex protobuf
  '';
in
{
  options.modules.languages.elixir = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Elixir / Erlang OTP runtime and elixir-ls.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      beam.packages.erlang_28.elixir_1_19
      erlang_28
      beam.packages.erlang_28."elixir-ls"
      install-elixir-escripts
    ];
  };
}
