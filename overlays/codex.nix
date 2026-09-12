final: prev:
let
  version = "0.154.0";

  # platform-specific binary info
  # upstream switched linux artifacts from -gnu to -musl in the rust-v0.122.0+ releases
  platform_info = {
    aarch64-darwin = {
      suffix = "aarch64-apple-darwin";
      hash = "sha256-NEMQoKWRwbGS4E/v8wQyGmmQfJSYuqrDMcp+FuvO+dc=";
      hostHash = "sha256-UA7ioC6lmK5RkFLn19jiAdHbAZhvMMIU70FDZF3Ib60=";
    };
    x86_64-darwin = {
      suffix = "x86_64-apple-darwin";
      hash = "sha256-EhnIN9j4E7STpCTBJcADi12coWJ5vG0/5s4Dej4Ypuc=";
      hostHash = "sha256-oPphQeWR9E3C2GpYnP55chIxe/ufo6bHMTHk27kzh/4=";
    };
    x86_64-linux = {
      suffix = "x86_64-unknown-linux-musl";
      hash = "sha256-1+GLJZeujyQvXzHunpDe70jbye3WNNmGj7ZDXQjAfwI=";
      hostHash = "sha256-po33zKI8bafN4XVnfffeYcc6I0rdEzOhJUuG1kGvAfc=";
    };
    aarch64-linux = {
      suffix = "aarch64-unknown-linux-musl";
      hash = "sha256-WDtI3zKAQhO9zTOMLlrbBrNDQIIfp1enJswKUk+jPCc=";
      hostHash = "sha256-IK76MCwgIrSW4ykRv5VKX3bH/XSca9ufvXEeMrZty/o=";
    };
  };

  system = final.stdenv.hostPlatform.system;
  info = platform_info.${system} or (throw "unsupported system: ${system}");

  src = final.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-${info.suffix}.tar.gz";
    hash = info.hash;
  };

  # Host binary for Code Mode execution
  hostSrc = final.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v${version}/codex-code-mode-host-${info.suffix}.tar.gz";
    hash = info.hostHash or "";
  };

in
{
  codex = final.stdenv.mkDerivation {
    pname = "codex";
    inherit version;

    srcs = [
      src
      hostSrc
    ];
    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 codex-${info.suffix} $out/bin/codex
      if [ -f codex-code-mode-host-${info.suffix} ]; then
        install -Dm755 codex-code-mode-host-${info.suffix} $out/bin/codex-code-mode-host
      fi
      runHook postInstall
    '';

    meta = with final.lib; {
      description = "OpenAI Codex CLI (prebuilt binary)";
      homepage = "https://github.com/openai/codex";
      license = licenses.asl20;
      mainProgram = "codex";
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
