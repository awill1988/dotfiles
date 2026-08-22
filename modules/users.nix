{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [ ./developer/profiles.nix ];

  options.users.primaryUser = {
    username = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "Operating system primary username";
    };
    fullName = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "Primary user display full name";
    };
  };
}
