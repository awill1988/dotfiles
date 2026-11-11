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
    unix = lib.unique (sensitivePaths.common ++ sensitivePaths.darwin ++ sensitivePaths.linux);
    all = lib.unique (
      sensitivePaths.common ++ sensitivePaths.darwin ++ sensitivePaths.linux ++ sensitivePaths.windows
    );
  };

  # Three-tier developer command & filesystem permissions
  defaultPermissions = {
    commands = {
      allow = [
        # Core inspection, text, stream & archive utilities
        "cat *"
        "head *"
        "tail *"
        "less *"
        "more *"
        "nl *"
        "od *"
        "xxd *"
        "hexdump *"
        "strings *"
        "ls *"
        "tree *"
        "pwd"
        "cd *"
        "stat *"
        "file *"
        "du *"
        "df *"
        "realpath *"
        "readlink *"
        "basename *"
        "dirname *"
        "find *"
        "fd *"
        "mdfind *"
        "mdls *"
        "which *"
        "whereis *"
        "type *"
        "command *"
        "grep *"
        "egrep *"
        "fgrep *"
        "rg *"
        "awk *"
        "gawk *"
        "sed *"
        "jq *"
        "yq *"
        "tr *"
        "cut *"
        "paste *"
        "column *"
        "sort *"
        "uniq *"
        "wc *"
        "comm *"
        "cmp *"
        "diff *"
        "colordiff *"
        "echo *"
        "printf *"
        "true"
        "false"
        "test *"
        "expr *"
        "bc *"
        "seq *"
        "sleep *"
        "timeout *"
        "time *"
        "watch *"
        "xargs *"
        "tee *"
        "env"
        "printenv *"
        "uname *"
        "hostname"
        "whoami"
        "id *"
        "groups *"
        "arch"
        "uptime"
        "date *"
        "cal *"
        "getconf *"
        "sysctl *"
        "sw_vers *"
        "system_profiler *"
        "ioreg *"
        "kextstat *"
        "pkgutil *"
        "otool *"
        "nm *"
        "ldd *"
        "objdump *"
        "dwarfdump *"
        "lipo -info *"
        "lipo -archs *"
        "codesign -d *"
        "codesign -v *"
        "codesign --verify *"
        "xattr -l *"
        "xattr -p *"
        "plutil -p *"
        "plutil -lint *"
        "plutil -extract *"
        "sips -g *"
        "defaults read *"
        "defaults domains *"
        "defaults find *"
        "log show *"
        "sfltool dumpbtm *"
        "fc-list *"
        "fc-match *"
        "ps *"
        "pgrep *"
        "lsof *"
        "shasum *"
        "sha256sum *"
        "sha512sum *"
        "md5 *"
        "md5sum *"
        "b2sum *"
        "base64 *"
        "mkdir *"
        "touch *"
        "cp *"
        "mv *"
        "ln *"
        "mktemp *"
        "chmod *"
        "tar *"
        "gzip *"
        "gunzip *"
        "zcat *"
        "bzip2 *"
        "xz *"
        "unzip *"
        "zip *"
        "zipinfo *"
        "rsync --dry-run *"
        "rsync -n *"
        "patch --dry-run *"
        "patch --check *"

        # Terminal, navigation, build, network & media tools
        "fzf *"
        "zoxide *"
        "mise *"
        "direnv status *"
        "direnv exec *"
        "direnv version *"
        "starship *"
        "just *"
        "make *"
        "gmake *"
        "cmake *"
        "ctest *"
        "ninja *"
        "pkg-config *"
        "curl *"
        "wget *"
        "dig *"
        "drill *"
        "nslookup *"
        "host *"
        "ping -c *"
        "nc -z *"
        "pdftotext *"
        "pdftoppm *"
        "pdfimages *"
        "pdfinfo *"
        "pdftohtml *"
        "pdfunite *"
        "pdfseparate *"
        "ffprobe *"
        "ffmpeg *"
        "identify *"
        "magick identify *"
        "midicsv *"
        "csvmidi *"
        "tmux list-sessions *"
        "tmux list-windows *"
        "tmux list-panes *"
        "tmux list-clients *"
        "tmux list-keys *"
        "tmux show-options *"
        "tmux show-option *"
        "tmux show-environment *"
        "tmux display-message *"
        "tmux capture-pane *"
        "tmux has-session *"
        "tmux info *"
        "tmux -V"

        # Nix, Darwin, Homebrew & mobile/desktop build tooling
        "nix *"
        "nixfmt *"
        "nil *"
        "cachix --version *"
        "nix-locate *"
        "nix-hash *"
        "nix-prefetch-url *"
        "nix-instantiate *"
        "nix-build *"
        "nix-shell *"
        "nix-env --query *"
        "nix-env -q *"
        "nix-store --query *"
        "nix-store -q *"
        "nix-store -qR *"
        "nix-store --gc --print-roots *"
        "nix-store --gc --print-dead *"
        "darwin-rebuild build *"
        "darwin-rebuild check *"
        "darwin-rebuild --list-generations *"
        "home-manager build *"
        "home-manager generations *"
        "home-manager packages *"
        "home-manager news *"
        "brew info *"
        "brew list *"
        "brew leaves *"
        "brew search *"
        "brew deps *"
        "brew uses *"
        "brew config *"
        "brew doctor *"
        "brew outdated *"
        "brew --prefix *"
        "brew --cellar *"
        "brew --cache *"
        "brew --repository *"
        "brew --version *"
        "brew bundle check *"
        "brew bundle list *"
        "brew services list *"
        "brew services info *"
        "apktool *"
        "bundletool *"
        "pod *"
        "eas *"
        "expo *"
        "fastlane *"
        "jadx *"
        "periphery *"
        "picotool *"
        "tuist *"
        "xcsift *"
        "xcodebuild *"
        "xcrun *"
        "xcode-select -p *"
        "xcode-select --print-path *"
        "xcode-select -v *"
        "swift *"
        "swiftc *"
        "swiftformat *"
        "swiftlint *"
        "adb *"
        "qgis --version *"
        "inkscape --version *"
        "blender --version *"

        # VCS & worktrees
        "git *"
        "gh *"
        "wt *"
        "git-ssh-sign *"

        # Rust toolchain
        "cargo *"
        "rustc *"
        "rustfmt *"
        "rustup *"
        "rust-analyzer *"
        "sccache *"
        "cargo-cache *"
        "cargo-sweep --dry-run *"

        # Go toolchain
        "go *"
        "gofmt *"
        "goimports *"
        "gopls *"
        "golangci-lint *"

        # Python & Ansible inspection toolchain
        "python *"
        "python3 *"
        "pytest *"
        "uv *"
        "uvx *"
        "poetry *"
        "pyright *"
        "ruff *"
        "mypy *"
        "pip *"
        "pip3 *"
        "ansible --version *"
        "ansible-inventory *"
        "ansible-config *"
        "ansible-doc *"
        "ansible-lint *"
        "ansible-playbook --syntax-check *"
        "ansible-playbook --check *"

        # Node, TypeScript & web toolchains
        "node *"
        "npm *"
        "pnpm *"
        "yarn *"
        "bun *"
        "bunx *"
        "npx *"
        "corepack *"
        "tsc *"
        "tsx *"
        "vitest *"
        "jest *"
        "eslint *"
        "biome *"
        "prettier *"
        "aicommits *"
        "aic *"

        # Elixir & Erlang toolchain
        "elixir *"
        "elixirc *"
        "iex *"
        "mix *"
        "erl *"
        "erlc *"
        "escript *"

        # Ruby toolchain
        "ruby *"
        "rbenv *"
        "gem *"
        "bundle *"
        "bundler *"
        "rake *"
        "rspec *"
        "rubocop *"
        "jekyll *"
        "solargraph *"

        # JVM & Kotlin toolchain
        "java *"
        "javac *"
        "javap *"
        "jar *"
        "javadoc *"
        "jdeps *"
        "keytool -list *"
        "keytool -printcert *"
        "gradle *"
        "./gradlew *"
        "gradlew *"
        "mvn *"
        "./mvnw *"
        "jdtls *"
        "kotlin-language-server *"
        "kotlinc *"

        # Static analysis & policy linters
        "shellcheck *"
        "shfmt *"
        "actionlint *"
        "yamllint *"
        "hadolint *"
        "tflint *"
        "checkov *"
        "semgrep *"

        # Cloud, containers, IaC & databases
        "aws *"
        "aws-vault *"
        "tofu *"
        "terraform *"
        "cf2tf *"
        "steampipe *"
        "grpcurl *"
        "docker *"
        "podman *"
        "lazydocker *"
        "kubectl *"
        "k9s *"
        "helm *"
        "gcloud *"
        "snow *"
        "sqlite3 *"
        "psql *"
        "pg_isready *"
        "pg_dump --schema-only *"
        "mysql *"
        "mariadb *"
        "jsonnet *"
        "jb *"
        "protoc *"
        "buf *"
        "openssl *"
        "trivy *"

        # Security scanners, identity inspection & agent orchestration
        "trufflehog *"
        "gitleaks *"
        "niro *"
        "harness2 *"
        "harness2-setup *"
        "harness2-check *"
        "harness2-report *"
        "whip-it *"
        "hold-up *"
        "hold-up-evaluate *"
        "profile-router *"
        "mcpgw-status *"
        "mcpgw-bridges *"
        "contextforge-mcp-sync *"
        "ssh-add -l *"
        "ssh-add -L *"
        "ssh-keygen -l *"
        "ssh-keygen -lf *"
        "ssh-keygen -F *"
        "ssh-keygen -Y verify *"
        "ssh-keygen -Y check-novalidate *"
        "ssh-keyscan *"
        "gpg --version *"
        "gpg --list-keys *"
        "gpg --list-public-keys *"
        "gpg --list-secret-keys *"
        "gpg --card-status *"
        "gpg --verify *"
        "gpgconf --list-dirs *"
        "gpgconf --list-components *"
        "ykman info *"
        "ykman list *"
        "ykman openpgp info *"
        "ykman piv info *"
        "ykman fido info *"
        "agy --version *"
        "agy --help *"
        "agy mcp list *"
        "agy plugin list *"
        "agy models *"
        "agy agents *"
        "claude --version *"
        "claude --help *"
        "claude mcp list *"
        "codex --version *"
        "codex --help *"
        "codex execpolicy check *"
        "opencode --version *"
        "opencode --help *"
      ];

      ask = [
        # VCS destructive history, branch/worktree deletion & merge/delete mutations
        "git push --force *"
        "git push -f *"
        "git push --force-with-lease *"
        "git push --delete *"
        "git push -d *"
        "git push * --force"
        "git push * -f"
        "git push * --force-with-lease"
        "git push * --delete"
        "git push * -d"
        "git reset --hard *"
        "git reset --merge *"
        "git clean -f *"
        "git clean -fd *"
        "git clean -fx *"
        "git clean -fxd *"
        "git clean -df *"
        "git clean --force *"
        "git branch -D *"
        "git branch --delete --force *"
        "git checkout -- ."
        "git checkout -f *"
        "git checkout --force *"
        "git restore ."
        "git restore --worktree ."
        "git stash drop *"
        "git stash clear *"
        "git worktree remove --force *"
        "git worktree remove -f *"
        "git filter-branch *"
        "git filter-repo *"
        "git tag -d *"
        "git tag --delete *"
        "wt remove --force *"
        "wt remove -f *"
        "wt prune *"
        "gh repo delete *"
        "gh repo archive *"
        "gh repo rename *"
        "gh repo edit --visibility *"
        "gh release delete *"
        "gh secret delete *"
        "gh secret set *"
        "gh variable delete *"
        "gh ssh-key delete *"
        "gh gpg-key delete *"
        "gh codespace delete *"
        "gh gist delete *"
        "gh run delete *"
        "gh cache delete *"
        "gh pr merge *"
        "gh pr close *"
        "gh issue delete *"
        "gh issue close *"
        "gh api -X DELETE *"
        "gh api --method DELETE *"
        "gh api * -X DELETE"
        "gh api * --method DELETE"

        # IaC state & infrastructure mutations
        "tofu apply *"
        "tofu destroy *"
        "tofu import *"
        "tofu taint *"
        "tofu untaint *"
        "tofu force-unlock *"
        "tofu state rm *"
        "tofu state mv *"
        "tofu state push *"
        "tofu state replace-provider *"
        "tofu workspace delete *"
        "tofu -chdir=* apply *"
        "tofu -chdir=* destroy *"
        "tofu -chdir=* import *"
        "tofu -chdir=* taint *"
        "tofu -chdir=* untaint *"
        "tofu -chdir=* force-unlock *"
        "tofu -chdir=* state rm *"
        "tofu -chdir=* state mv *"
        "tofu -chdir=* state push *"
        "tofu -chdir=* workspace delete *"
        "terraform apply *"
        "terraform destroy *"
        "terraform import *"
        "terraform taint *"
        "terraform untaint *"
        "terraform force-unlock *"
        "terraform state rm *"
        "terraform state mv *"
        "terraform state push *"
        "terraform state replace-provider *"
        "terraform workspace delete *"
        "terraform -chdir=* apply *"
        "terraform -chdir=* destroy *"
        "terraform -chdir=* import *"
        "terraform -chdir=* taint *"
        "terraform -chdir=* untaint *"
        "terraform -chdir=* force-unlock *"
        "terraform -chdir=* state rm *"
        "terraform -chdir=* state mv *"
        "terraform -chdir=* state push *"
        "terraform -chdir=* workspace delete *"

        # AWS, GCP & Snowflake destructive operations
        "aws s3 rb *"
        "aws s3 rm *"
        "aws s3 mv *"
        "aws s3 sync * --delete"
        "aws * delete-*"
        "aws * terminate-*"
        "aws * remove-*"
        "aws * deregister-*"
        "aws * purge-*"
        "aws * destroy-*"
        "aws * batch-delete-*"
        "aws * put-bucket-policy *"
        "aws * delete-bucket*"
        "aws-vault remove *"
        "aws-vault clear *"
        "aws-vault rotate *"
        "gcloud projects delete *"
        "gcloud compute instances delete *"
        "gcloud compute disks delete *"
        "gcloud container clusters delete *"
        "gcloud sql instances delete *"
        "gcloud run services delete *"
        "gcloud iam service-accounts delete *"
        "gcloud secrets delete *"
        "gcloud storage rm *"
        "gcloud storage buckets delete *"
        "snow object drop *"
        "snow stage remove *"

        # Container & Kubernetes mutations/deletions
        "docker rm *"
        "docker rmi *"
        "docker prune *"
        "docker system prune *"
        "docker volume rm *"
        "docker volume prune *"
        "docker image rm *"
        "docker image prune *"
        "docker container rm *"
        "docker container prune *"
        "docker network rm *"
        "docker network prune *"
        "docker builder prune *"
        "docker compose down *"
        "docker compose rm *"
        "docker kill *"
        "docker stop *"
        "docker push *"
        "podman rm *"
        "podman rmi *"
        "podman prune *"
        "podman system prune *"
        "podman volume rm *"
        "podman volume prune *"
        "podman image rm *"
        "podman image prune *"
        "podman container rm *"
        "podman container prune *"
        "podman network rm *"
        "podman network prune *"
        "podman compose down *"
        "podman compose rm *"
        "podman kill *"
        "podman stop *"
        "podman push *"
        "kubectl delete *"
        "kubectl apply *"
        "kubectl patch *"
        "kubectl replace *"
        "kubectl edit *"
        "kubectl drain *"
        "kubectl cordon *"
        "kubectl taint *"
        "kubectl scale *"
        "kubectl rollout restart *"
        "kubectl rollout undo *"
        "helm uninstall *"
        "helm delete *"
        "helm upgrade *"
        "helm install *"
        "helm rollback *"

        # Store pruning, package publishing, DB drops & overwriting flags
        "nix store gc *"
        "nix store delete *"
        "nix profile wipe-history *"
        "nix-store --delete *"
        "nix-collect-garbage *"
        "cargo publish *"
        "cargo yank *"
        "cargo-cache --autoclean *"
        "rustup self uninstall *"
        "npm publish *"
        "npm unpublish *"
        "npm deprecate *"
        "pnpm publish *"
        "yarn publish *"
        "bun publish *"
        "poetry publish *"
        "uv publish *"
        "pip uninstall *"
        "pip3 uninstall *"
        "uv pip uninstall *"
        "gem push *"
        "gem yank *"
        "mix hex.publish *"
        "mix hex.retire *"
        "mix ecto.drop *"
        "mix ecto.reset *"
        "rake db:drop *"
        "rake db:reset *"
        "rake db:schema:load *"
        "bundle exec rake db:drop *"
        "bundle exec rake db:reset *"
        "eas submit *"
        "eas build:delete *"
        "fastlane deploy *"
        "fastlane release *"
        "pod trunk push *"
        "pod trunk delete *"
        "picotool erase *"
        "picotool load *"
        "picotool reboot *"
        "adb uninstall *"
        "adb reboot *"
        "adb sideload *"
        "dropdb *"
        "chmod -R *"
        "sed -i *"
        "find -delete *"
        "find * -delete"
        "find * -exec rm *"
        "curl -X DELETE *"
        "curl --request DELETE *"
        "curl * -X DELETE"
        "curl * --request DELETE"

        # Secret & keychain extraction
        "pass *"
        "sops *"
        "security find-generic-password *"
        "security find-internet-password *"
        "security dump-keychain *"
        "security export *"
        "security delete-generic-password *"
        "security delete-internet-password *"
      ];

      deny = [
        # Prevent catastrophic host/root deletion & raw block device writes
        "rm -rf /"
        "rm -rf ~"
        "rm -rf ~/*"
        "rm -rf $HOME"
        "rm -rf $HOME/*"
        "rm -rf /Users"
        "rm -rf /home"
        "rm -rf /System"
        "rm -rf /Library"
        "rm -rf /etc"
        "rm -rf /usr"
        "rm -rf /var"
        "rm -rf /nix"
        "mkfs *"
        "dd *"

        # Prevent unprompted shell reads/copies of sensitive credential stores
        "cat ~/.ssh"
        "cat ~/.ssh/*"
        "cat ~/.aws"
        "cat ~/.aws/*"
        "cat ~/.gnupg"
        "cat ~/.gnupg/*"
        "cat ~/.kube"
        "cat ~/.kube/*"
        "cat ~/.password-store"
        "cat ~/.password-store/*"
        "cat ~/.netrc"
        "cat /etc/shadow"
        "cat /etc/master.passwd"
        "head ~/.ssh"
        "head ~/.ssh/*"
        "head ~/.aws"
        "head ~/.aws/*"
        "head ~/.gnupg/*"
        "head ~/.kube/*"
        "head ~/.netrc"
        "tail ~/.ssh"
        "tail ~/.ssh/*"
        "tail ~/.aws"
        "tail ~/.aws/*"
        "tail ~/.gnupg/*"
        "tail ~/.kube/*"
        "tail ~/.netrc"
        "less ~/.ssh/*"
        "less ~/.aws/*"
        "less ~/.gnupg/*"
        "less ~/.kube/*"
        "less ~/.netrc"
        "cp ~/.ssh/* *"
        "cp ~/.aws/* *"
        "cp ~/.gnupg/* *"
        "cp ~/.kube/* *"
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
      sensitive = sensitivePaths.unix;
    };
  };

  # Helper: Determine whether a sensitive path entry is a file/glob rather than a directory
  isSensitiveFileOrGlob =
    p:
    (lib.hasInfix "*" p)
    || (builtins.elem p [
      "~/.netrc"
      "/etc/master.passwd"
      "/etc/sudoers"
      "/etc/shadow"
      "/etc/gshadow"
      "id_rsa"
      "id_ed25519"
    ]);

  # Helper: Escape regex metacharacters for RE2 / AGY regex rules
  escapeRegex =
    s:
    lib.stringAsChars (
      c:
      if
        builtins.elem c [
          "."
          "+"
          "?"
          "^"
          "$"
          "("
          ")"
          "["
          "]"
          "{"
          "}"
          "|"
          "\\"
        ]
      then
        "\\${c}"
      else
        c
    ) s;

  # Helper: Convert a globbed command pattern containing '*' into an RE2-compatible AGY regex
  globToAgyRegex =
    base:
    let
      parts = lib.filter (p: p != "") (lib.splitString " " base);
      isAwsServiceGlob =
        (builtins.length parts >= 3) && (builtins.head parts == "aws") && (builtins.elemAt parts 1 == "*");
      renderToken =
        tok:
        let
          hasHomePrefix = lib.hasPrefix "~/" tok;
          strippedTok = if hasHomePrefix then lib.removePrefix "~/" tok else tok;
          pieces = lib.splitString "*" strippedTok;
          escapedJoined = lib.concatMapStringsSep "\\S*" escapeRegex pieces;
        in
        if hasHomePrefix then
          "(?:~|\\$HOME|/Users/[^/\\s]+|/home/[^/\\s]+)/${escapedJoined}"
        else
          escapedJoined;

      renderParts =
        idx:
        if idx >= builtins.length parts then
          ""
        else
          let
            tok = builtins.elemAt parts idx;
            isLast = idx == (builtins.length parts - 1);
          in
          if idx == 1 && isAwsServiceGlob then
            "(?:--[a-z-]+=\\S+\\s+|--(?:profile|region|endpoint-url|output)\\s+\\S+\\s+|--no-[a-z-]+\\s+)*\\S+"
            + (if isLast then "" else "\\s+" + renderParts (idx + 1))
          else if tok == "*" then
            if isLast then "\\S+(?:\\s+.*)?" else "(?:\\S+\\s+)*" + renderParts (idx + 1)
          else
            (renderToken tok) + (if isLast then "" else "\\s+" + renderParts (idx + 1));
    in
    "command(regex:^${renderParts 0}(?:\\s+.*)?$)";

  # Helper: Clean and format bash command for Claude
  toClaudeCommand =
    cmd:
    if lib.hasPrefix "Bash(" cmd then
      [ cmd ]
    else
      let
        base = lib.removeSuffix " *" cmd;
      in
      if lib.hasInfix "*" base then
        if lib.hasSuffix "*" base then
          [ "Bash(${base})" ]
        else
          [
            "Bash(${base})"
            "Bash(${base} *)"
          ]
      else
        [
          "Bash(${base})"
          "Bash(${base} *)"
        ];

  # Helper: Clean and format bash command for AGY v1.5+ (literal token prefix or regex: opt-in)
  toAgyCommand =
    cmd:
    if lib.hasPrefix "command(" cmd then
      cmd
    else
      let
        base = lib.removeSuffix " *" cmd;
      in
      if lib.hasInfix "*" base then globToAgyRegex base else "command(${base})";

  # Helper: Convert server/tool to Claude mcp__<server>__<tool>
  toClaudeMcp =
    tool:
    if lib.hasPrefix "mcp__" tool then
      tool
    else
      "mcp__${builtins.replaceStrings [ "/" ] [ "__" ] tool}";

  # Helper: Convert server/tool to AGY mcp(<server>/<tool>)
  toAgyMcp = tool: if lib.hasPrefix "mcp(" tool then tool else "mcp(${tool})";

  # Environment-variable prefixes commonly prepended to cloud/container/language CLIs in Claude
  claudeToolEnvMap = {
    aws = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
      "AWS_DEFAULT_REGION=*"
      "AWS_SDK_LOAD_CONFIG=*"
    ];
    aws-vault = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
      "AWS_DEFAULT_REGION=*"
    ];
    tofu = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
      "AWS_DEFAULT_REGION=*"
      "TF_WORKSPACE=*"
      "TF_IN_AUTOMATION=*"
      "TF_LOG=*"
    ];
    terraform = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
      "AWS_DEFAULT_REGION=*"
      "TF_WORKSPACE=*"
      "TF_IN_AUTOMATION=*"
      "TF_LOG=*"
    ];
    steampipe = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
    ];
    snow = [
      "AWS_PROFILE=*"
      "SNOWFLAKE_DEFAULT_CONNECTION_NAME=*"
    ];
    docker = [
      "DOCKER_HOST=*"
      "DOCKER_BUILDKIT=*"
      "COMPOSE_PROJECT_NAME=*"
    ];
    podman = [ "CONTAINER_HOST=*" ];
    kubectl = [ "KUBECONFIG=*" ];
    helm = [ "KUBECONFIG=*" ];
    trivy = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
    ];
    psql = [
      "PGPASSWORD=*"
      "PGHOST=*"
      "PGPORT=*"
      "PGUSER=*"
      "PGDATABASE=*"
    ];
    dropdb = [
      "PGPASSWORD=*"
      "PGHOST=*"
      "PGUSER=*"
    ];
    cargo = [
      "RUST_LOG=*"
      "RUST_BACKTRACE=*"
      "CARGO_TERM_COLOR=*"
    ];
    go = [
      "CGO_ENABLED=*"
      "GOOS=*"
      "GOARCH=*"
    ];
    uv = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
      "PYTHONPATH=*"
    ];
    python = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
      "PYTHONPATH=*"
    ];
    python3 = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
      "PYTHONPATH=*"
    ];
    pytest = [
      "AWS_PROFILE=*"
      "AWS_REGION=*"
      "PYTHONPATH=*"
    ];
    poetry = [
      "AWS_PROFILE=*"
      "PYTHONPATH=*"
    ];
    pnpm = [
      "NODE_ENV=*"
      "CI=*"
    ];
    npm = [
      "NODE_ENV=*"
      "CI=*"
    ];
    yarn = [
      "NODE_ENV=*"
      "CI=*"
    ];
    bun = [
      "NODE_ENV=*"
      "CI=*"
    ];
    node = [ "NODE_ENV=*" ];
    mix = [ "MIX_ENV=*" ];
    rake = [ "RAILS_ENV=*" ];
    bundle = [ "RAILS_ENV=*" ];
    rspec = [ "RAILS_ENV=*" ];
  };

  # Translates general permissions into Claude settings permissions block
  toClaudePermissions =
    perms:
    let
      allowInput = perms.commands.allow or [ ];
      askInput = perms.commands.ask or defaultPermissions.commands.ask;
      denyInput = perms.commands.deny or [ ];

      firstToken = cmd: builtins.head (lib.splitString " " (lib.removeSuffix " *" cmd));
      allowedBins = lib.unique (map firstToken allowInput);

      envAllowCommands = lib.concatMap (
        bin:
        if builtins.elem bin allowedBins && builtins.hasAttr bin claudeToolEnvMap then
          map (envPref: "Bash(${envPref} ${bin} *)") claudeToolEnvMap.${bin}
        else
          [ ]
      ) (builtins.attrNames claudeToolEnvMap);

      envAskCommands = lib.concatMap (
        cmd:
        let
          bin = firstToken cmd;
          prefixes = claudeToolEnvMap.${bin} or [ ];
        in
        lib.concatMap (envPref: toClaudeCommand "${envPref} ${cmd}") prefixes
      ) askInput;

      allowCommands = lib.unique ((lib.concatMap toClaudeCommand allowInput) ++ envAllowCommands);
      askCommands = lib.unique ((lib.concatMap toClaudeCommand askInput) ++ envAskCommands);
      denyCommands = lib.unique (lib.concatMap toClaudeCommand denyInput);

      allowMcp = map toClaudeMcp (perms.mcp.allow or [ ]);
      denyMcp = map toClaudeMcp (perms.mcp.deny or [ ]);

      allowReads =
        if (perms.filesystem.allowRead or [ ]) != [ ] then
          [
            "Read(//nix/store/**)"
            "Read(//tmp/**)"
            "Read(//private/tmp/**)"
            "Read(//var/folders/**)"
            "Read(//opt/homebrew/**)"
            "Read(//usr/local/**)"
            "Read(~/projects/**)"
            "Read(~/.config/nix/**)"
            "Read(~/.local/share/agent-skills/**)"
            "Read(~/.claude/skills/**)"
            "Read(~/.gemini/skills/**)"
            "Read(~/.gemini/antigravity-cli/builtin/**)"
          ]
        else
          [ ];

      # Sensitive path reads should never be auto-approved
      unixSensitive = lib.filter (
        p: !(lib.hasPrefix "%" p) && !(lib.hasInfix "\\" p) && !(lib.hasPrefix "C:" p)
      ) (perms.filesystem.sensitive or [ ]);

      toClaudeReadPath = p: if lib.hasPrefix "/" p then "/${p}" else p;

      sensitiveDenyReads = lib.concatMap (
        p:
        let
          cp = toClaudeReadPath p;
        in
        if isSensitiveFileOrGlob p then
          if (lib.hasPrefix "/" p) || (lib.hasPrefix "~/" p) then
            [ "Read(${cp})" ]
          else
            [
              "Read(${p})"
              "Read(**/${p})"
            ]
        else
          [
            "Read(${cp})"
            "Read(${cp}/*)"
            "Read(${cp}/**)"
          ]
      ) unixSensitive;
    in
    {
      allow = lib.unique (allowCommands ++ allowReads ++ allowMcp);
      ask = askCommands;
      deny = lib.unique (denyCommands ++ denyMcp ++ sensitiveDenyReads);
      disableAutoMode = "disable";
      defaultMode = "default";
    };

  # Translates general permissions into AGY settings permissions block
  toAgyPermissions =
    perms:
    let
      allowInput = perms.commands.allow or [ ];
      askInput = perms.commands.ask or defaultPermissions.commands.ask;
      denyInput = perms.commands.deny or [ ];

      allowCommands = lib.unique (map toAgyCommand allowInput);
      askCommands = lib.unique (map toAgyCommand askInput);
      denyCommands = lib.unique (map toAgyCommand denyInput);

      allowMcp = map toAgyMcp (perms.mcp.allow or [ ]);
      denyMcp = map toAgyMcp (perms.mcp.deny or [ ]);

      allowRead = if (perms.filesystem.allowRead or [ ]) != [ ] then [ "read_file(*)" ] else [ ];
      allowWrite = if (perms.filesystem.allowWrite or [ ]) != [ ] then [ "write_file(*)" ] else [ ];

      # Filter out Windows paths that trigger parse failures in AGY permission grant store
      unixSensitive = lib.filter (
        p: !(lib.hasPrefix "%" p) && !(lib.hasInfix "\\" p) && !(lib.hasPrefix "C:" p)
      ) (perms.filesystem.sensitive or [ ]);

      # Sensitive reads require interactive user permission via "ask"
      sensitiveAskReads = lib.concatMap (
        p:
        if isSensitiveFileOrGlob p then
          (
            if (lib.hasPrefix "/" p) || (lib.hasPrefix "~/" p) then
              [ "read_file(${p})" ]
            else
              [
                "read_file(${p})"
                "read_file(**/${p})"
              ]
          )
          ++ [
            (toAgyCommand "cat ${p}")
            (toAgyCommand "head ${p}")
            (toAgyCommand "tail ${p}")
            (toAgyCommand "less ${p}")
          ]
        else
          [
            "read_file(${p})"
            "read_file(${p}/*)"
            "read_file(${p}/**)"
            (toAgyCommand "cat ${p}")
            (toAgyCommand "cat ${p}/*")
            (toAgyCommand "head ${p}")
            (toAgyCommand "head ${p}/*")
            (toAgyCommand "tail ${p}")
            (toAgyCommand "tail ${p}/*")
            (toAgyCommand "less ${p}/*")
          ]
      ) unixSensitive;
    in
    {
      allow = allowCommands ++ allowMcp ++ allowRead ++ allowWrite;
      deny = lib.unique (denyCommands ++ denyMcp);
      ask = lib.unique (askCommands ++ sensitiveAskReads);
    };

  # Concrete AWS services & destructive operations for Codex Starlark union rules
  codexAwsServices = [
    "apigateway"
    "apigatewayv2"
    "autoscaling"
    "backup"
    "batch"
    "cloudformation"
    "cloudfront"
    "cloudtrail"
    "cloudwatch"
    "cognito-idp"
    "configservice"
    "dynamodb"
    "ec2"
    "ecr"
    "ecs"
    "eks"
    "elasticache"
    "elbv2"
    "emr"
    "events"
    "firehose"
    "glue"
    "guardduty"
    "iam"
    "kinesis"
    "kms"
    "lambda"
    "logs"
    "organizations"
    "rds"
    "redshift"
    "route53"
    "s3api"
    "s3control"
    "secretsmanager"
    "ses"
    "sns"
    "sqs"
    "ssm"
    "sso-admin"
    "stepfunctions"
    "wafv2"
  ];

  codexAwsDestructiveOps = [
    "batch-delete-image"
    "delete-access-key"
    "delete-alarms"
    "delete-api"
    "delete-auto-scaling-group"
    "delete-backup-vault"
    "delete-bucket"
    "delete-bucket-policy"
    "delete-cache-cluster"
    "delete-change-set"
    "delete-cluster"
    "delete-configuration-recorder"
    "delete-db-cluster"
    "delete-db-instance"
    "delete-DB-snapshot"
    "delete-db-snapshot"
    "delete-delivery-stream"
    "delete-detector"
    "delete-distribution"
    "delete-domain-name"
    "delete-environment"
    "delete-event-bus"
    "delete-File-system"
    "delete-function"
    "delete-group"
    "delete-hosted-zone"
    "delete-identity"
    "delete-instance-profile"
    "delete-internet-gateway"
    "delete-job"
    "delete-key-pair"
    "delete-launch-template"
    "delete-listener"
    "delete-load-balancer"
    "delete-log-group"
    "delete-log-stream"
    "delete-nat-gateway"
    "delete-network-acl"
    "delete-nodegroup"
    "delete-object"
    "delete-objects"
    "delete-parameter"
    "delete-parameters"
    "delete-policy"
    "delete-policy-version"
    "delete-queue"
    "delete-recovery-point"
    "delete-replication-group"
    "delete-repository"
    "delete-rest-api"
    "delete-role"
    "delete-role-policy"
    "delete-route"
    "delete-route-table"
    "delete-rule"
    "delete-secret"
    "delete-security-group"
    "delete-service"
    "delete-snapshot"
    "delete-stack"
    "delete-stack-set"
    "delete-state-machine"
    "delete-stream"
    "delete-subnet"
    "delete-table"
    "delete-target-group"
    "delete-topic"
    "delete-trail"
    "delete-user"
    "delete-user-policy"
    "delete-user-pool"
    "delete-volume"
    "delete-vpc"
    "delete-web-acl"
    "deregister-image"
    "deregister-instances-from-load-balancer"
    "deregister-targets"
    "deregister-task-definition"
    "purge-queue"
    "put-bucket-policy"
    "remove-Permission"
    "remove-permission"
    "remove-role-from-instance-profile"
    "remove-targets"
    "remove-user-from-group"
    "schedule-key-deletion"
    "terminate-clusters"
    "terminate-instances"
    "terminate-job-flows"
    "terminate-workspaces"
  ];

  # Translates general permissions into Codex Starlark default.rules
  toCodexRules =
    perms:
    let
      allowInput = perms.commands.allow or [ ];
      askInput = perms.commands.ask or defaultPermissions.commands.ask;
      denyInput = perms.commands.deny or [ ];

      # Only emit literal prefix_rules for patterns without embedded '*' globs
      toLiteralTokenList =
        cmd:
        let
          base = lib.removeSuffix " *" cmd;
        in
        if lib.hasInfix "*" base then
          null
        else
          let
            parts = lib.filter (p: p != "") (lib.splitString " " base);
          in
          if parts == [ ] then null else parts;

      collectTokenLists = cmds: lib.unique (lib.filter (x: x != null) (map toLiteralTokenList cmds));

      renderTokenList = parts: "[${lib.concatMapStringsSep ", " builtins.toJSON parts}]";

      renderRules =
        decision: cmds:
        lib.concatMapStringsSep "\n" (parts: ''
          prefix_rule(
              pattern = ${renderTokenList parts},
              decision = "${decision}",
          )'') (collectTokenLists cmds);

      hasAwsAsk = builtins.any (c: lib.hasPrefix "aws * " c) askInput;
      hasGitPushAsk = builtins.any (c: lib.hasPrefix "git push * " c) askInput;

      unionPromptRules = lib.concatStringsSep "\n" (
        (lib.optional hasAwsAsk ''
          prefix_rule(
              pattern = ["aws", ${renderTokenList codexAwsServices}, ${renderTokenList codexAwsDestructiveOps}],
              decision = "prompt",
          )'')
        ++ (lib.optional hasGitPushAsk ''
          prefix_rule(
              pattern = ["git", "push", ["origin", "upstream", "production", "staging"], ["--force", "-f", "--force-with-lease", "--delete", "-d"]],
              decision = "prompt",
          )'')
      );

      unionForbiddenRules = ''
        prefix_rule(
            pattern = [["cat", "head", "tail", "less", "cp"], ["~/.ssh/id_ed25519", "~/.ssh/id_rsa", "~/.ssh/config", "~/.ssh/authorized_keys", "~/.aws/credentials", "~/.aws/config", "~/.kube/config"]],
            decision = "forbidden",
        )'';
    in
    ''
      # Auto-generated by Nix native permissions harness
      ${renderRules "forbidden" denyInput}
      ${unionForbiddenRules}
      ${renderRules "prompt" askInput}
      ${unionPromptRules}
      ${renderRules "allow" allowInput}
    '';

  # Ordered OpenCode bash permission entries (last-matching-rule-wins: * -> allow -> ask -> deny)
  toOpencodeBashEntries =
    perms:
    let
      allowInput = perms.commands.allow or [ ];
      askInput = perms.commands.ask or defaultPermissions.commands.ask;
      denyInput = perms.commands.deny or [ ];

      expandEntry =
        decision: cmd:
        let
          base = lib.removeSuffix " *" cmd;
        in
        if lib.hasInfix "*" base then
          [
            {
              name = cmd;
              value = decision;
            }
          ]
        else
          [
            {
              name = base;
              value = decision;
            }
            {
              name = "${base} *";
              value = decision;
            }
          ];

      rawEntries = [
        {
          name = "*";
          value = "ask";
        }
      ]
      ++ (lib.concatMap (expandEntry "allow") allowInput)
      ++ (lib.concatMap (expandEntry "ask") askInput)
      ++ (lib.concatMap (expandEntry "deny") denyInput);

      # Deduplicate while preserving the LAST occurrence so deny > ask > allow > * holds
      dedupKeepLast =
        entries:
        let
          step =
            acc: item:
            if builtins.elem item.name acc.seen then
              acc
            else
              {
                seen = acc.seen ++ [ item.name ];
                items = [ item ] ++ acc.items;
              };
        in
        (lib.foldl' step {
          seen = [ ];
          items = [ ];
        } (lib.reverseList entries)).items;
    in
    dedupKeepLast rawEntries;

  # Attribute-set form of OpenCode permissions
  toOpencodePermissions = perms: {
    bash = builtins.listToAttrs (toOpencodeBashEntries perms);
  };

  # Deterministic JSON fragment for OpenCode `permission` preserving exact rule evaluation order
  toOpencodePermissionsJson =
    perms:
    let
      entries = toOpencodeBashEntries perms;
      bashBody = lib.concatMapStringsSep "," (
        e: "${builtins.toJSON e.name}:${builtins.toJSON e.value}"
      ) entries;
    in
    "{\"bash\":{${bashBody}}}";
}
