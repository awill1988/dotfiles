{ pkgs }:
pkgs.runCommand "drive-mcp-contracts"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    BRIDGE_PY = ./scripts/bridge.py;
  }
  ''
    python3 ${./test_bridge.py}
    touch "$out"
  ''
