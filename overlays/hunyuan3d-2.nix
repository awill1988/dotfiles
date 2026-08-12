final: prev:
let
  version = "2.0.2";
  rev = "f8db63096c8282cb27354314d896feba5ba6ff8a";

  src = final.fetchFromGitHub {
    owner = "Tencent";
    repo = "Hunyuan3D-2";
    inherit rev;
    hash = "sha256-tbPuhnCqUcSnttdTs/DxcYLQWterNlbWyNqTHmUxcOs=";
  };

  # use a uv-managed venv instead of python312.withPackages — pytorch has no
  # binary substitute for aarch64-darwin in nixpkgs and takes 30-60 min to
  # build from source. PyPI ships pre-built wheels for macOS ARM64.
  #
  # the venv is created on first run in $HY3DGEN_VENV (defaults to
  # $XDG_CACHE_HOME/hy3dgen/venv). subsequent starts reuse it instantly.
  server = final.writeShellScriptBin "hunyuan3d-server" ''
    set -euo pipefail

    : "''${XDG_CACHE_HOME:=$HOME/.cache}"
    : "''${HY3DGEN_MODELS:=$XDG_CACHE_HOME/hy3dgen}"
    : "''${HY3DGEN_VENV:=$XDG_CACHE_HOME/hy3dgen/venv}"
    export HY3DGEN_MODELS
    mkdir -p "$HY3DGEN_MODELS"

    ${final.lib.optionalString final.stdenv.isDarwin ''
      export PYTORCH_ENABLE_MPS_FALLBACK=1
    ''}

    # bootstrap venv on first run; reuse on subsequent starts
    if [[ ! -f "$HY3DGEN_VENV/pyvenv.cfg" ]]; then
      echo "bootstrapping python venv at $HY3DGEN_VENV (one-time) ..."
      ${final.uv}/bin/uv venv "$HY3DGEN_VENV" --python 3.12
      ${final.uv}/bin/uv pip install --python "$HY3DGEN_VENV/bin/python" \
        torch torchvision \
        diffusers transformers trimesh rembg onnxruntime \
        omegaconf einops opencv-python accelerate pygltflib pymeshlab \
        huggingface-hub safetensors numpy tqdm \
        fastapi uvicorn pillow xatlas
      echo "venv ready"
    fi

    export PYTHONPATH=${src}:''${PYTHONPATH:-}
    exec "$HY3DGEN_VENV/bin/python" ${src}/api_server.py "$@"
  '';
in
{
  hunyuan3d-2 = server.overrideAttrs (_: {
    passthru = { inherit src version; };
  });
}
