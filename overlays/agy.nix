final: prev:
let
  inherit (prev) lib;

  version = "1.1.11";
  base_url = "https://github.com/google-antigravity/antigravity-cli/releases/download/${version}";

  platform_info = {
    aarch64-darwin = {
      url = "${base_url}/agy_cli_mac_arm64.tar.gz";
      hash = "sha256-l8uQnTDbsr8jLT0Q5dvIvACPDnAwQAtRWhguSQvdbwg=";
    };
    x86_64-darwin = {
      url = "${base_url}/agy_cli_mac_x64.tar.gz";
      hash = "sha256-pjoYmlmgvRrrcCNqygdUJ49Bikrm2O+ZyONha/p6PnM=";
    };
    x86_64-linux = {
      url = "${base_url}/agy_cli_linux_x64.tar.gz";
      hash = "sha256-yu8d1MmcV97h0d7CtsZ3Jt9TXqSexx6rrdNtr/giPRk=";
    };
    aarch64-linux = {
      url = "${base_url}/agy_cli_linux_arm64.tar.gz";
      hash = "sha256-86A3E+PjzIRHfhFdP9neHCMjhrCThLqGkN9vwMsKu/M=";
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

    # The tarball expands to a single top-level file named `antigravity`, not a directory.
    sourceRoot = ".";

    nativeBuildInputs = lib.optionals prev.stdenv.isLinux [ prev.autoPatchelfHook ];

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
