{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.security.ssh;
in
{
  options.modules.security.ssh = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable SSH configuration and host match blocks.";
    };
  };

  config = mkIf cfg.enable {
    programs.ssh = {
      enable = true;
      enableDefaultConfig = false;
      matchBlocks = {
        "*" = {
          host = "*";
          controlMaster = "auto";
          controlPath = "/tmp/ssh-%u-%r@%h:%p";
          controlPersist = "60";
          forwardAgent = true;
          serverAliveInterval = 60;
          hashKnownHosts = true;
          identityFile = [ "~/.ssh/id_ed25519" ];
        };
        "private-nets" = {
          host = "master-* node-*";
          user = "admin";
          extraOptions = {
            StrictHostKeyChecking = "accept-new";
            UserKnownHostsFile = "~/.ssh/known_hosts";
          };
        };
      };
      extraConfig = "";
    };
  };
}
