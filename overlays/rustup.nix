final: prev: {
  rustup = prev.rustup.overrideAttrs (oldAttrs: {
    doCheck = false;
    preBuild = (oldAttrs.preBuild or "") + ''
      export RUST_MIN_STACK=16777216
    '';
  });
}
