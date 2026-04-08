final: prev:
let
  version = "5.7.1";

  # platform-specific release info
  platform_info = {
    aarch64-darwin = {
      archive = "podman-remote-release-darwin_arm64.zip";
      hash = "sha256-5e7TqzbJO+yXOCQZdP+G0XO9ElFiGo8veuyTPFefSWg=";
      binary_path = "podman-${version}/usr/bin/podman";
      helper_path = "podman-${version}/usr/bin/podman-mac-helper";
    };
    x86_64-darwin = {
      archive = "podman-remote-release-darwin_amd64.zip";
      hash = "sha256-qoBDMvi8yLZdNONpvMjerV1qrNpZzwoutEeBtgJqNhE=";
      binary_path = "podman-${version}/usr/bin/podman";
      helper_path = "podman-${version}/usr/bin/podman-mac-helper";
    };
    x86_64-linux = {
      archive = "podman-remote-static-linux_amd64.tar.gz";
      hash = "sha256-amZ8gR2vLUNAz12PEmTFrpkCUZykFMZ2UUNZ1cFlV28=";
      binary_path = "bin/podman-remote-static-linux_amd64";
      helper_path = null;
    };
    aarch64-linux = {
      archive = "podman-remote-static-linux_arm64.tar.gz";
      hash = "sha256-T68V4hFBZhJDQZpimdJbewCCUZjJNDmaYmWbIBl2NeQ=";
      binary_path = "bin/podman-remote-static-linux_arm64";
      helper_path = null;
    };
  };

  system = final.stdenv.hostPlatform.system;
  is_darwin = final.stdenv.isDarwin;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://github.com/containers/podman/releases/download/v${version}/${info.archive}";
    hash = info.hash;
  };

  # darwin needs gvproxy and vfkit for podman machine
  darwin_helpers = final.lib.optionals is_darwin [
    prev.gvproxy
    prev.vfkit
  ];
in
{
  podman = final.stdenv.mkDerivation {
    pname = "podman";
    inherit version src;

    nativeBuildInputs = [
      prev.makeWrapper
    ] ++ final.lib.optionals is_darwin [
      prev.unzip
    ];

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    unpackPhase =
      if is_darwin then ''
        unzip $src
      '' else ''
        tar -xzf $src
      '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out/bin
      install -Dm755 "${info.binary_path}" $out/bin/podman
      ${final.lib.optionalString (info.helper_path != null) ''
        install -Dm755 "${info.helper_path}" $out/bin/podman-mac-helper
      ''}

      runHook postInstall
    '';

    postFixup = final.lib.optionalString is_darwin ''
      wrapProgram $out/bin/podman \
        --prefix PATH : ${final.lib.makeBinPath darwin_helpers}
    '';

    meta = with prev.lib; {
      description = "Podman container engine (prebuilt binary from GitHub releases)";
      homepage = "https://github.com/containers/podman";
      changelog = "https://github.com/containers/podman/releases/tag/v${version}";
      license = licenses.asl20;
      mainProgram = "podman";
      platforms = builtins.attrNames platform_info;
      maintainers = [ ];
    };
  };
}
