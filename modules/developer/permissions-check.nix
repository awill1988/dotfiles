{ pkgs }:
let
  inherit (pkgs) lib;
  permsLib = import ./permissions.nix { inherit lib; };

  agyJson = pkgs.writeText "agy-permissions-test.json" (
    builtins.toJSON (permsLib.toAgyPermissions permsLib.defaultPermissions)
  );
  claudeJson = pkgs.writeText "claude-permissions-test.json" (
    builtins.toJSON (permsLib.toClaudePermissions permsLib.defaultPermissions)
  );
  codexRules = pkgs.writeText "codex-rules-test.rules" (
    permsLib.toCodexRules permsLib.defaultPermissions
  );
  opencodeJson = pkgs.writeText "opencode-permissions-test.json" (
    permsLib.toOpencodePermissionsJson permsLib.defaultPermissions
  );

  verifyScript = pkgs.writeText "verify-agent-permissions.py" ''
    import ast
    import fnmatch
    import json
    import pathlib
    import re
    import sys

    agy = json.loads(pathlib.Path(sys.argv[1]).read_text())
    claude = json.loads(pathlib.Path(sys.argv[2]).read_text())
    codex_text = pathlib.Path(sys.argv[3]).read_text()
    opencode_pairs = json.loads(
        pathlib.Path(sys.argv[4]).read_text(),
        object_pairs_hook=list,
    )

    # 1. AGY invariants & simulated engine (deny > ask > allow)
    for tier in ("allow", "ask", "deny"):
        assert tier in agy and len(agy[tier]) > 0, f"AGY missing {tier}"
        for entry in agy[tier]:
            assert " *)" not in entry, f"AGY literal trailing wildcard bug: {entry}"
            for bad in ("*.key/*", "*.pem/*", "*.pfx/*", "*.p12/*", "/etc/shadow/*", "id_rsa/*"):
                assert bad not in entry, f"AGY malformed sensitive glob {bad} in {entry}"
            if entry.startswith("command(regex:") and entry.endswith(")"):
                pat = entry[len("command(regex:") : -1]
                for unsupported in ("(?=", "(?!", "(?<=", "(?<!"):
                    assert unsupported not in pat, f"Non-RE2 lookaround in {entry}"
                re.compile(pat)

    for expected in (
        "command(git)",
        "command(tofu)",
        "command(aws)",
        "command(uv)",
        "command(pdftotext)",
        "command(brew info)",
    ):
        assert expected in agy["allow"], f"AGY missing {expected}"

    def agy_matches(rule: str, cmd: str) -> bool:
        if not (rule.startswith("command(") and rule.endswith(")")):
            return False
        inner = rule[len("command(") : -1]
        if inner.startswith("regex:"):
            return re.search(inner[len("regex:") :], cmd) is not None
        rule_tokens = inner.split()
        cmd_tokens = cmd.split()
        return len(cmd_tokens) >= len(rule_tokens) and cmd_tokens[: len(rule_tokens)] == rule_tokens

    def agy_eval(cmd: str) -> str:
        for r in agy["deny"]:
            if agy_matches(r, cmd):
                return "deny"
        for r in agy["ask"]:
            if agy_matches(r, cmd):
                return "ask"
        for r in agy["allow"]:
            if agy_matches(r, cmd):
                return "allow"
        return "ask"

    for safe_cmd in (
        "git status",
        "git -C /tmp/repo diff",
        "tofu plan -no-color",
        "aws sts get-caller-identity",
        "aws ec2 describe-instances --filters Name=tag:Action,Values=delete-me",
        "uv run pytest",
        "brew info jq",
        "pdftotext sample.pdf -",
    ):
        assert agy_eval(safe_cmd) == "allow", f"AGY expected allow for {safe_cmd!r}, got {agy_eval(safe_cmd)}"

    for ask_cmd in (
        "git push --force origin main",
        "git push origin main --force",
        "git reset --hard HEAD~1",
        "tofu apply",
        "tofu -chdir=infra destroy",
        "aws ec2 terminate-instances --instance-ids i-123",
        "aws --profile arro-staging iam delete-role --role-name foo",
        "aws s3 rb s3://my-bucket",
        "gh repo delete awill1988/demo",
        "docker system prune -af",
        "kubectl delete pod api-0",
        "find . -name '*.tmp' -delete",
        "pass show personal/token",
    ):
        assert agy_eval(ask_cmd) == "ask", f"AGY expected ask for {ask_cmd!r}, got {agy_eval(ask_cmd)}"

    for deny_cmd in (
        "rm -rf /",
        "rm -rf ~",
        "dd if=/dev/zero of=/dev/disk0",
        "cat ~/.ssh/id_ed25519",
        "cat /Users/adam/.aws/credentials",
    ):
        assert agy_eval(deny_cmd) == "deny", f"AGY expected deny for {deny_cmd!r}, got {agy_eval(deny_cmd)}"

    # 2. Claude invariants & simulated engine (deny > ask > allow)
    for tier in ("allow", "ask", "deny"):
        assert tier in claude and len(claude[tier]) > 0, f"Claude missing {tier}"

    for expected in (
        "Bash(git)",
        "Bash(git *)",
        "Bash(tofu)",
        "Bash(tofu *)",
        "Bash(brew outdated)",
        "Bash(brew outdated *)",
        "Bash(AWS_PROFILE=* aws *)",
        "Bash(AWS_PROFILE=* tofu *)",
        "Bash(MIX_ENV=* mix *)",
        "Read(//nix/store/**)",
        "Read(//tmp/**)",
        "mcp__contextforge__*",
    ):
        assert expected in claude["allow"], f"Claude allow missing {expected}"

    for expected_deny in (
        "Read(~/.ssh/**)",
        "Read(//etc/shadow)",
        "Read(**/*.key)",
        "mcp__fivetran__pause_connector",
    ):
        assert expected_deny in claude["deny"], f"Claude deny missing {expected_deny}"

    for entry in claude["deny"]:
        assert "*.key/*" not in entry and "*.pem/*" not in entry, f"Claude malformed glob: {entry}"

    def claude_bash_eval(cmd: str) -> str:
        for tier in ("deny", "ask", "allow"):
            for r in claude[tier]:
                if r.startswith("Bash(") and r.endswith(")"):
                    pat = r[len("Bash(") : -1]
                    if fnmatch.fnmatchcase(cmd, pat):
                        return tier
        return "ask"

    assert claude_bash_eval('git commit -m "make tests pass now"') == "allow"
    assert claude_bash_eval("AWS_PROFILE=arro-staging AWS_REGION=us-west-2 tofu plan") == "allow"
    assert claude_bash_eval("AWS_PROFILE=arro-staging AWS_REGION=us-west-2 tofu apply") == "ask"
    assert claude_bash_eval("AWS_PROFILE=arro-prod aws ec2 terminate-instances --instance-ids i-1") == "ask"
    assert claude_bash_eval("MIX_ENV=test mix test") == "allow"
    assert claude_bash_eval("MIX_ENV=prod mix ecto.drop") == "ask"
    assert claude_bash_eval("cat ~/.ssh/id_ed25519") == "deny"

    # 3. Codex Starlark syntax, deduplication & simulated engine (forbidden > prompt > allow)
    tree = ast.parse(codex_text)
    codex_rules = []
    seen_codex = set()
    for node in tree.body:
        assert isinstance(node, ast.Expr) and isinstance(node.value, ast.Call)
        assert isinstance(node.value.func, ast.Name) and node.value.func.id == "prefix_rule"
        kw = {k.arg: ast.literal_eval(k.value) for k in node.value.keywords}
        pattern = kw["pattern"]
        decision = kw["decision"]
        assert decision in ("allow", "prompt", "forbidden")
        for tok in pattern:
            if isinstance(tok, str):
                assert "*" not in tok, f"Codex wildcard token not allowed: {pattern}"
            elif isinstance(tok, list):
                assert len(tok) > 0
                for sub in tok:
                    assert isinstance(sub, str) and "*" not in sub, f"Codex wildcard in union: {sub}"
            else:
                raise AssertionError(f"Unexpected token type in {pattern}")
        sig = (decision, repr(pattern))
        assert sig not in seen_codex, f"Duplicate Codex rule: {sig}"
        seen_codex.add(sig)
        codex_rules.append((decision, pattern))

    decisions_present = {d for d, _ in codex_rules}
    assert decisions_present == {"allow", "prompt", "forbidden"}, f"Missing tiers: {decisions_present}"

    def codex_match(pattern, argv):
        if len(argv) < len(pattern):
            return False
        for expected, actual in zip(pattern, argv):
            if isinstance(expected, list):
                if actual not in expected:
                    return False
            elif expected != actual:
                return False
        return True

    def codex_eval(argv):
        matched = {d for d, pat in codex_rules if codex_match(pat, argv)}
        for tier in ("forbidden", "prompt", "allow"):
            if tier in matched:
                return tier
        return "prompt"

    assert codex_eval(["git", "status"]) == "allow"
    assert codex_eval(["tofu", "plan"]) == "allow"
    assert codex_eval(["tofu", "destroy"]) == "prompt"
    assert codex_eval(["aws", "sts", "get-caller-identity"]) == "allow"
    assert codex_eval(["aws", "ec2", "terminate-instances", "--instance-ids", "i-1"]) == "prompt"
    assert codex_eval(["git", "push", "origin", "--force"]) == "prompt"
    assert codex_eval(["rm", "-rf", "/"]) == "forbidden"
    assert codex_eval(["cat", "~/.ssh/id_ed25519"]) == "forbidden"

    # 4. OpenCode key ordering & last-matching-rule-wins evaluation
    top_dict = dict(opencode_pairs)
    bash_pairs = top_dict["bash"]
    keys = [k for k, _ in bash_pairs]
    assert len(keys) == len(set(keys)), "Duplicate keys in OpenCode permission.bash"
    assert bash_pairs[0] == ("*", "ask"), f"First OpenCode rule must be *=ask, got {bash_pairs[0]}"

    phase_order = {"allow": 1, "ask": 2, "deny": 3}
    highest_phase = 0
    for k, v in bash_pairs[1:]:
        p = phase_order[v]
        assert p >= highest_phase, f"OpenCode ordering violated at {k!r}={v!r} after phase {highest_phase}"
        highest_phase = p

    def opencode_eval(cmd: str) -> str:
        result = "ask"
        for pat, dec in bash_pairs:
            if fnmatch.fnmatchcase(cmd, pat):
                result = dec
        return result

    assert opencode_eval("git status") == "allow"
    assert opencode_eval("git push --force origin main") == "ask"
    assert opencode_eval("aws sts get-caller-identity") == "allow"
    assert opencode_eval("aws ec2 terminate-instances --instance-ids i-1") == "ask"
    assert opencode_eval("rm foo.txt") == "ask"
    assert opencode_eval("rm -rf /") == "deny"
    assert opencode_eval("cat ~/.ssh/id_ed25519") == "deny"

    print("All cross-agent permission invariants verified.")
  '';
in
pkgs.runCommand "agent-permissions-contracts"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    export PYTHONDONTWRITEBYTECODE=1
    python3 "${verifyScript}" "${agyJson}" "${claudeJson}" "${codexRules}" "${opencodeJson}"
    touch "$out"
  ''
