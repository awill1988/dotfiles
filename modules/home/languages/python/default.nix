{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.modules.languages.python;
in
{
  options.modules.languages.python = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Python environment, pyright, uv, and poetry.";
    };
  };

  config = mkIf cfg.enable {
    home.packages = with pkgs; [
      (python3.withPackages (
        ps: with ps; [
          tkinter
          ansible-core
          pip
          setuptools
          wheel
          numpy
          cython
          openai
          (ps.buildPythonPackage rec {
            pname = "ansibug";
            version = "0.3.1";
            pyproject = true;
            src = pkgs.fetchPypi {
              inherit pname version;
              sha256 = "10rp4jjqldwm4d31fnwliddzg4c8wiyi2qznvkk8yfbwsvhsjqwq";
            };
            nativeBuildInputs = with ps; [
              setuptools
              wheel
            ];
            propagatedBuildInputs = with ps; [ ansible-core ];
          })
        ]
      ))
      uv
      poetry
      pyright
    ];
  };
}
