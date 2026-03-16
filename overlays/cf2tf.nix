final: prev: {
  cf2tf = final.writeShellScriptBin "cf2tf" ''
    exec ${final.uv}/bin/uvx cf2tf==0.9.2 "$@"
  '';
}
