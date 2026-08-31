{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.karabiner-elements;
  is_darwin = pkgs.stdenv.isDarwin;
  base_settings = builtins.fromJSON (builtins.readFile ./karabiner.json);

  tartarus_modification_type = lib.types.submodule {
    options = {
      from_key_code = lib.mkOption {
        type = lib.types.str;
        description = "Physical key_code emitted by Tartarus Pro.";
        example = "q";
      };
      to_key_code = lib.mkOption {
        type = lib.types.str;
        description = "Target key_code to emit (for example, keypad key codes).";
        example = "keypad_7";
      };
    };
  };

  tartarus_device_conditions =
    lib.optionals (cfg.tartarus_pro.vendor_id != null && cfg.tartarus_pro.product_id != null)
      [
        {
          type = "device_if";
          identifiers = [
            {
              vendor_id = cfg.tartarus_pro.vendor_id;
              product_id = cfg.tartarus_pro.product_id;
              is_keyboard = cfg.tartarus_pro.is_keyboard;
            }
          ];
        }
      ];

  tartarus_frontmost_application_conditions =
    lib.optionals
      (
        cfg.tartarus_pro.frontmost_application.bundle_identifiers != [ ]
        || cfg.tartarus_pro.frontmost_application.file_paths != [ ]
      )
      [
        (
          {
            type = "frontmost_application_if";
          }
          // lib.optionalAttrs (cfg.tartarus_pro.frontmost_application.bundle_identifiers != [ ]) {
            bundle_identifiers = cfg.tartarus_pro.frontmost_application.bundle_identifiers;
          }
          // lib.optionalAttrs (cfg.tartarus_pro.frontmost_application.file_paths != [ ]) {
            file_paths = cfg.tartarus_pro.frontmost_application.file_paths;
          }
        )
      ];

  tartarus_conditions = tartarus_device_conditions ++ tartarus_frontmost_application_conditions;

  tartarus_mapping_modifications = map (from_key_code: {
    inherit from_key_code;
    to_key_code = cfg.tartarus_pro.mapping.${from_key_code};
  }) (builtins.attrNames cfg.tartarus_pro.mapping);

  tartarus_modifications = cfg.tartarus_pro.simple_modifications ++ tartarus_mapping_modifications;
  tartarus_from_keys = map (m: m.from_key_code) tartarus_modifications;
  tartarus_has_duplicate_from_keys =
    builtins.length tartarus_from_keys != builtins.length (lib.unique tartarus_from_keys);

  tartarus_rules = lib.optionals (cfg.tartarus_pro.enable && tartarus_modifications != [ ]) [
    {
      description = cfg.tartarus_pro.rule_description;
      manipulators = map (m: {
        type = "basic";
        from = {
          key_code = m.from_key_code;
          modifiers = {
            optional = [ "any" ];
          };
        };
        to = [ { key_code = m.to_key_code; } ];
        conditions = tartarus_conditions;
      }) tartarus_modifications;
    }
  ];

  profile_exists = builtins.any (p: (p.name or "") == cfg.profile_name) (
    cfg.settings.profiles or [ ]
  );

  merged_settings = cfg.settings // {
    profiles = map (
      profile:
      if (profile.name or "") == cfg.profile_name then
        profile
        // {
          complex_modifications =
            let
              current = profile.complex_modifications or { };
            in
            current
            // {
              rules = (current.rules or [ ]) ++ cfg.extra_rules ++ tartarus_rules;
            };
        }
      else
        profile
    ) (cfg.settings.profiles or [ ]);
  };

  settings_json = pkgs.writeText "karabiner.json" (builtins.toJSON merged_settings);
in
{
  options.programs.karabiner-elements = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Karabiner-Elements";
    };
    install_method = lib.mkOption {
      type = lib.types.enum [
        "nix"
        "homebrew"
        "none"
      ];
      default = "nix";
      description = "How to install Karabiner-Elements. Use homebrew on macOS if privileged components fail from Nix install.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.karabiner-elements;
      description = "Karabiner-Elements package to install.";
    };

    profile_name = lib.mkOption {
      type = lib.types.str;
      default = "Default profile";
      description = "Profile name in karabiner.json where generated rules are appended.";
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = base_settings;
      description = "Base karabiner.json settings before generated rules are appended.";
    };

    extra_rules = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [ ];
      description = "Additional complex modification rules appended to the selected profile.";
    };

    tartarus_pro = {
      enable = lib.mkEnableOption "Tartarus Pro key remaps";
      rule_description = lib.mkOption {
        type = lib.types.str;
        default = "tartarus pro keypad remaps";
        description = "Rule description shown in Karabiner-Elements.";
      };
      vendor_id = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "USB vendor_id from Karabiner-EventViewer; null applies to any keyboard.";
      };
      product_id = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "USB product_id from Karabiner-EventViewer; null applies to any keyboard.";
      };
      is_keyboard = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Set device condition to keyboard devices.";
      };
      frontmost_application = {
        bundle_identifiers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Regex bundle identifiers for apps where tartarus remaps should apply.";
          example = [ "^com\\.avid\\.Sibelius.*$" ];
        };
        file_paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Regex app file paths where tartarus remaps should apply.";
          example = [ "^/Applications/Sibelius.*\\.app/" ];
        };
      };
      simple_modifications = lib.mkOption {
        type = lib.types.listOf tartarus_modification_type;
        default = [ ];
        description = "Simple Tartarus key remaps from source key_code to target key_code.";
      };
      mapping = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Shortcut mapping from source key_code to target key_code.";
        example = {
          q = "keypad_7";
          w = "keypad_8";
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = is_darwin;
        message = "programs.karabiner-elements is only supported on darwin.";
      }
      {
        assertion = (cfg.tartarus_pro.vendor_id == null) == (cfg.tartarus_pro.product_id == null);
        message = "set both tartarus_pro.vendor_id and tartarus_pro.product_id, or leave both null.";
      }
      {
        assertion = profile_exists;
        message = "programs.karabiner-elements.profile_name was not found in programs.karabiner-elements.settings.profiles.";
      }
      {
        assertion = !tartarus_has_duplicate_from_keys;
        message = "tartarus_pro mappings contain duplicate from_key_code values across mapping and simple_modifications.";
      }
    ];

    home.packages = lib.optionals (cfg.install_method == "nix") [ cfg.package ];
    xdg.configFile."karabiner/karabiner.json" = {
      source = settings_json;
      force = true;
    };
  };
}
