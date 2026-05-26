final: prev:
let
  inherit (prev) lib;

  # Google Antigravity CLI (agy). Distributed as a single dynamically-linked
  # binary named `antigravity` inside a per-platform tarball, served from a
  # Google Cloud Storage bucket. Manifests live at
  #   https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/<platform>.json
  # and point at the build-id-stamped URLs encoded below.
  version = "1.0.2";
  build_id = "6109799369277440";

  base_url = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-${build_id}";

  platform_info = {
    aarch64-darwin = {
      url = "${base_url}/darwin-arm/cli_mac_arm64.tar.gz";
      hash = "sha256-jvFVBeZakXxKIdE5y+5qw5T7ubMSTzxtdGvSw0oqKNs=";
    };
    x86_64-darwin = {
      url = "${base_url}/darwin-x64/cli_mac_x64.tar.gz";
      hash = "sha256-ddjHsXkrrX76TwVA7Hy6MxCyS/5tfpwFEWkS+jOPLug=";
    };
    x86_64-linux = {
      url = "${base_url}/linux-x64/cli_linux_x64.tar.gz";
      hash = "sha256-9sfKgNUJkzO/IpZ2RzvREeDapqDY23xTKt9lA7Dqrck=";
    };
    aarch64-linux = {
      url = "${base_url}/linux-arm/cli_linux_arm64.tar.gz";
      hash = "sha256-ylqnAh/9ppSybxp5KsllsFPdLOQmzmIbdtk43zlnXfw=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system for agy: ${system}");

  src = prev.fetchurl {
    url = info.url;
    hash = info.hash;
  };
in
{
  agy = prev.stdenv.mkDerivation {
    pname = "agy";
    inherit version src;

    # The tarball expands to a single top-level file named `antigravity`,
    # not a directory.
    sourceRoot = ".";

    nativeBuildInputs = lib.optionals prev.stdenv.isLinux [
      prev.autoPatchelfHook
    ];

    buildInputs = lib.optionals prev.stdenv.isLinux [
      prev.stdenv.cc.cc.lib
      prev.zlib
    ];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 antigravity "$out/bin/agy"
      runHook postInstall
    '';

    meta = {
      description = "Google Antigravity CLI (agy)";
      homepage = "https://antigravity.google";
      license = lib.licenses.unfree;
      platforms = builtins.attrNames platform_info;
      mainProgram = "agy";
    };
  };
}
