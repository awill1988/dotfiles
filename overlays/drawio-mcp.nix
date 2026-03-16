final: prev:
let
  version = "1.1.3";
  rev = "ee83179b9e204d119965c2f1b9390a0f78d386c1";

  src = final.fetchFromGitHub {
    owner = "jgraph";
    repo = "drawio-mcp";
    inherit rev;
    hash = "sha256-UpuvufkqmrcrJh0XT/IX2tPWOyVmYCf58mfnisX9gqg=";
  };
in
{
  drawio-mcp = final.buildNpmPackage {
    pname = "drawio-mcp";
    inherit version;
    src = "${src}/mcp-tool-server";
    npmDepsHash = "sha256-ufgxe7zCTUU06IROtrTd5+lrqXHaNNqip8Oe/ZQsZ6Q=";
    dontNpmBuild = true;

    meta = with final.lib; {
      description = "Official draw.io MCP server for diagram creation and editing";
      homepage = "https://github.com/jgraph/drawio-mcp";
      license = licenses.asl20;
      mainProgram = "drawio-mcp";
      maintainers = [ ];
    };
  };
}
