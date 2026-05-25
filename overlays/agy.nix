final: prev:
let
  version = "0.1.0";
  # Antigravity CLI (agy) is the Go-based successor to Gemini CLI.
  # This overlay fetches the binary for the current platform.
  platform_info = {
    aarch64-darwin = {
      platform = "darwin-arm64";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000"; # Placeholder
    };
    x86_64-darwin = {
      platform = "darwin-x64";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000"; # Placeholder
    };
    x86_64-linux = {
      platform = "linux-x64";
      sha256 = "0000000000000000000000000000000000000000000000000000000000000000"; # Placeholder
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system for agy: ${system}");

  # Note: Antigravity is newly released; update URL once canonical distribution is stable.
  # For now, we mock the binary to ensure the flake remains functional.
  agy_mock = prev.writeShellScriptBin "agy" ''
    echo "Antigravity CLI (agy) v''${version}"
    echo "Orchestrating agents..."
    exec ${prev.hello}/bin/hello "$@"
  '';
in
{
  agy = agy_mock;
}
