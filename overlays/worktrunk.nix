final: prev:
let
  version = "0.80.0";

  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-iiuwU8S8gN6n2c5sIh/wONEKPS3KLcj2DRsaCU+ng6k=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-qomKowFherr5HLMHjeTIwRREoGEBbcj23YCqF8wcRr4=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-musl";
      hash = "sha256-Uyzj7V7ssb4nTJJbWIf2FnHiQ0pMolYbmorJN527oZk=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-musl";
      hash = "sha256-NHsmDBsESlOncgszGB18ZtzelF771gXXhOW2pWFsF+k=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://github.com/max-sixty/worktrunk/releases/download/v${version}/worktrunk-${info.suffix}.tar.xz";
    hash = info.hash;
  };
in
{
  worktrunk = final.stdenv.mkDerivation {
    pname = "worktrunk";
    inherit version src;

    sourceRoot = "worktrunk-${info.suffix}";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 wt $out/bin/wt
      if [ -f git-wt ]; then
        install -Dm755 git-wt $out/bin/git-wt
      fi
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "Worktrunk is a CLI for Git worktree management, designed for parallel AI agent workflows";
      homepage = "https://github.com/max-sixty/worktrunk";
      license = with licenses; [
        mit
        asl20
      ];
      mainProgram = "wt";
      platforms = [
        "aarch64-darwin"
        "x86_64-darwin"
        "x86_64-linux"
        "aarch64-linux"
      ];
      maintainers = [ ];
    };
  };
}
