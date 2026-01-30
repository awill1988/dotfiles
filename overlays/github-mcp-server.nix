final: prev:
let
  version = "0.28.1";

  # map nix system to release archive name and hash
  platform_map = {
    "x86_64-linux" = {
      suffix = "Linux_x86_64";
      hash = "sha256-fZUsvcQ7lsMZgDL0cMvy1ZprrN+bVM2UmtzchOw9VDw=";
    };
    "aarch64-linux" = {
      suffix = "Linux_arm64";
      hash = "sha256-+Lwvp5fUoM7b4l1aeJaY5dTXseGgSwxQ/68A/U6g3Ic=";
    };
    "x86_64-darwin" = {
      suffix = "Darwin_x86_64";
      hash = "sha256-Pv2MAKyILISStRr+7o5mSo3r/9ssI3ePmEWDP2X67Qo=";
    };
    "aarch64-darwin" = {
      suffix = "Darwin_arm64";
      hash = "sha256-Kk9Wiw+zCHagJY1eyNT46MxIL477tTj1bKZq+jqBF8Y=";
    };
  };

  platform =
    platform_map.${final.stdenv.hostPlatform.system}
      or (throw "unsupported platform: ${final.stdenv.hostPlatform.system}");

  src = final.fetchzip {
    url = "https://github.com/github/github-mcp-server/releases/download/v${version}/github-mcp-server_${platform.suffix}.tar.gz";
    hash = platform.hash;
    stripRoot = false;
  };
in
{
  github-mcp-server = final.stdenv.mkDerivation {
    pname = "github-mcp-server";
    inherit version src;

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 github-mcp-server $out/bin/github-mcp-server
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "GitHub MCP Server for AI assistants";
      homepage = "https://github.com/github/github-mcp-server";
      license = licenses.mit;
      mainProgram = "github-mcp-server";
      platforms = builtins.attrNames platform_map;
      maintainers = [ ];
    };
  };
}
