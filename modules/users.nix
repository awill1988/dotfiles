{ lib, ... }:
let
  inherit (lib) mkOption types;
in
{
  options.users.primaryUser = {
    username = mkOption {
      type = with types; nullOr str;
      default = null;
    };
    fullName = mkOption {
      type = with types; nullOr str;
      default = null;
    };
    git = {
      github = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      signingKey = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      signingFormat = mkOption {
        type =
          with types;
          nullOr (enum [
            "openpgp"
            "ssh"
          ]);
        default = null;
      };
      email = mkOption {
        type = with types; nullOr str;
        default = null;
      };
      emailSecondary = mkOption {
        type = with types; nullOr str;
        default = null;
      };
    };
  };
}
