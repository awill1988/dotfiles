{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.cloud.infra;
in
{
  options.modules.cloud.infra = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable cloud infrastructure, database, container management, and API tooling.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      cf2tf
      pkgs-unstable.opentofu
      k9s
      lazydocker
      steampipe
      grpcurl
      sqlite
      mariadb.client
      postgresql
      jsonnet
      qemu
      protobuf
      openssl
      onnxruntime
    ];
  };
}
