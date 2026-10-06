{ lib }:
rec {
  # Cross-platform sensitive path definitions
  sensitivePaths = {
    common = [
      "~/.ssh"
      "~/.aws"
      "~/.gnupg"
      "~/.kube"
      "~/.azure"
      "~/.password-store"
      "~/.netrc"
      "~/.1password"
      "*.pem"
      "*.key"
      "id_rsa"
      "id_rsa.*"
      "id_ed25519"
      "id_ed25519.*"
      "*.pfx"
      "*.p12"
    ];
    darwin = [
      "~/Library/Keychains"
      "~/Library/Messages"
      "~/Library/Mail"
      "~/Library/Cookies"
      "/Library/Keychains"
      "/etc/master.passwd"
      "/etc/sudoers"
      "/private/var/db/dslocal"
    ];
    linux = [
      "/etc/shadow"
      "/etc/gshadow"
      "/etc/sudoers"
      "/etc/sudoers.d"
      "/etc/ssl/private"
      "/root"
      "~/.local/share/keyrings"
    ];
    windows = [
      "%USERPROFILE%\\.ssh"
      "%USERPROFILE%\\.aws"
      "%USERPROFILE%\\.kube"
      "%APPDATA%\\Microsoft\\Protect"
      "%APPDATA%\\Microsoft\\Vault"
      "%LOCALAPPDATA%\\Microsoft\\Credentials"
      "C:\\Windows\\System32\\config"
      "C:/Users/*/.ssh"
      "C:/Users/*/.aws"
      "C:/Users/*/.kube"
      "C:/Windows/System32/config"
    ];
    all = lib.unique (
      sensitivePaths.common ++ sensitivePaths.darwin ++ sensitivePaths.linux ++ sensitivePaths.windows
    );
  };

  # Default coarse-grained permissions for developer workflows
  defaultPermissions = {
    commands = {
      allow = [
        # Inspection & Navigation
        "cat *"
        "echo *"
        "ls *"
        "ls"
        "rg *"
        "grep *"
        "find *"
        "head *"
        "tail *"
        "which *"
        "file *"
        "wc *"
        "pwd"
        "env"
        "whoami"
        "ps *"
        "stat *"
        "basename *"
        "dirname *"
        "realpath *"
        "readlink *"
        "date *"
        "diff *"
        "lsof *"
        "lsof"
        "true"
        "false"

        # Data & File editing tools
        "jq *"
        "sed *"
        "awk *"
        "mkdir *"
        "cp *"
        "mv *"

        # Text & Stream processing
        "sort *"
        "sort"
        "uniq *"
        "uniq"
        "xargs *"
        "tr *"
        "tee *"
        "cut *"
        "touch *"
        "uname *"
        "uname"
        "tree *"
        "tree"
        "fd *"
        "cd *"
        "cd"

        # Archive tools
        "tar *"
        "gzip *"
        "gunzip *"
        "unzip *"

        # VCS & Network
        "git *"
        "gh *"
        "curl *"

        # Build & Package Managers
        "nix *"
        "cargo *"
        "pnpm *"
        "npm *"
        "yarn *"
        "bun *"
        "go *"
        "python3 *"
        "python *"
        "pytest *"
        "make *"

        # Cloud & Infrastructure
        "aws *"
      ];
      deny = [
        # Prevent destructive host operations
        "rm -rf /"
        "rm -rf /*"
        "mkfs *"
        "dd *"
        # Prevent unprompted reading of sensitive directories
        "cat ~/.ssh"
        "cat ~/.ssh/*"
        "cat ~/.aws"
        "cat ~/.aws/*"
        "cat ~/.gnupg"
        "cat ~/.gnupg/*"
        "cat /etc/shadow"
        "cat /etc/master.passwd"
        "head ~/.ssh"
        "head ~/.ssh/*"
        "head ~/.aws"
        "head ~/.aws/*"
        "tail ~/.ssh"
        "tail ~/.ssh/*"
        "tail ~/.aws"
        "tail ~/.aws/*"
        "cp ~/.ssh/* *"
        "cp ~/.aws/* *"
      ];
    };

    mcp = {
      allow = [
        "contextforge/*"
        "drive/*"
        "blender/*"
        "firefox-devtools/*"
        "icon-composer/*"
      ];
      deny = [
        "fivetran/pause_connector"
        "fivetran/resume_connector"
        "fivetran/create_dynamic_connector"
        "fivetran/migrate_connector"
        "fivetran/reload_connector_schema"
        "fivetran/update_connector_schema"
        "fivetran/modify_sync_frequency"
      ];
    };

    filesystem = {
      allowRead = [ "*" ];
      allowWrite = [ ];
      sensitive = sensitivePaths.all;
    };
  };

  # Helper: Clean and format bash command for Claude
  toClaudeCommand =
    cmd:
    if lib.hasPrefix "Bash(" cmd then
      cmd
    else if lib.hasSuffix "*" cmd then
      "Bash(${cmd})"
    else if !(lib.hasInfix " " cmd) then
      [
        "Bash(${cmd})"
        "Bash(${cmd} *)"
      ]
    else
      "Bash(${cmd})";

  # Helper: Clean and format bash command for AGY
  toAgyCommand =
    cmd:
    if lib.hasPrefix "command(" cmd then
      cmd
    else if lib.hasSuffix "*" cmd then
      "command(${cmd})"
    else if !(lib.hasInfix " " cmd) then
      [
        "command(${cmd})"
        "command(${cmd} *)"
      ]
    else
      "command(${cmd})";

  # Helper: Convert server/tool to Claude mcp__<server>__<tool>
  toClaudeMcp =
    tool:
    if lib.hasPrefix "mcp__" tool then
      tool
    else
      "mcp__${builtins.replaceStrings [ "/" ] [ "__" ] tool}";

  # Helper: Convert server/tool to AGY mcp(<server>/<tool>)
  toAgyMcp = tool: if lib.hasPrefix "mcp(" tool then tool else "mcp(${tool})";

  # Translates general permissions into Claude settings permissions block
  toClaudePermissions =
    perms:
    let
      rawAllowCommands = map toClaudeCommand perms.commands.allow;
      allowCommands = lib.unique (lib.flatten rawAllowCommands);
      allowMcp = map toClaudeMcp perms.mcp.allow;

      rawDenyCommands = map toClaudeCommand perms.commands.deny;
      denyCommands = lib.unique (lib.flatten rawDenyCommands);
      denyMcp = map toClaudeMcp perms.mcp.deny;

      # Sensitive path reads should never be auto-approved
      sensitiveDenyReads = lib.flatten (
        map (p: [
          "Read(${p})"
          "Read(${p}/*)"
          "Read(${p}/**)"
        ]) (perms.filesystem.sensitive or [ ])
      );
    in
    {
      allow = allowCommands ++ allowMcp;
      deny = lib.unique (denyCommands ++ denyMcp ++ sensitiveDenyReads);
    };

  # Translates general permissions into AGY settings permissions block
  toAgyPermissions =
    perms:
    let
      rawAllowCommands = map toAgyCommand perms.commands.allow;
      allowCommands = lib.unique (lib.flatten rawAllowCommands);
      allowMcp = map toAgyMcp perms.mcp.allow;
      allowRead = if (perms.filesystem.allowRead or [ ]) != [ ] then [ "read(*)" ] else [ ];
      allowWrite = if (perms.filesystem.allowWrite or [ ]) != [ ] then [ "write(*)" ] else [ ];

      rawDenyCommands = map toAgyCommand perms.commands.deny;
      denyCommands = lib.unique (lib.flatten rawDenyCommands);
      denyMcp = map toAgyMcp perms.mcp.deny;

      # Sensitive reads require interactive user permission via "ask"
      sensitiveAskReads = lib.flatten (
        map (p: [
          "read(${p})"
          "read(${p}/*)"
          "read(${p}/**)"
          "command(cat ${p})"
          "command(cat ${p}/*)"
          "command(head ${p})"
          "command(head ${p}/*)"
          "command(tail ${p})"
          "command(tail ${p}/*)"
        ]) (perms.filesystem.sensitive or [ ])
      );
    in
    {
      allow = allowCommands ++ allowMcp ++ allowRead ++ allowWrite;
      deny = lib.unique (denyCommands ++ denyMcp);
      ask = lib.unique sensitiveAskReads;
    };

  # Translates general permissions into Codex default rules
  toCodexRules =
    perms:
    let
      toTokens =
        cmd:
        let
          cleaned = lib.removeSuffix " *" (lib.removeSuffix "*" cmd);
          parts = lib.filter (p: p != "") (lib.splitString " " cleaned);
        in
        map (p: "\"${p}\"") parts;

      allowRules = lib.concatStringsSep "\n" (
        map (cmd: ''
          prefix_rule(
              pattern = [${lib.concatStringsSep ", " (toTokens cmd)}],
              decision = "allow",
          )
        '') perms.commands.allow
      );

      denyRules = lib.concatStringsSep "\n" (
        map (cmd: ''
          prefix_rule(
              pattern = [${lib.concatStringsSep ", " (toTokens cmd)}],
              decision = "deny",
          )
        '') perms.commands.deny
      );
    in
    ''
      # Auto-generated by Nix native permissions harness
      ${denyRules}
      ${allowRules}
    '';
}
