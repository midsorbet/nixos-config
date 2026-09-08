{pkgs}: let
  version = "1.0.0";
in
  pkgs.buildNpmPackage {
    pname = "cua-mcp-client";
    inherit version;

    src = pkgs.lib.fileset.toSource {
      root = ./.;
      fileset = pkgs.lib.fileset.unions [
        ./package.json
        ./package-lock.json
        ./cua-mcp-client.ts
      ];
    };

    npmDepsHash = "sha256-vtWjhdLBv2Qy4R6ZjJRwbFTaS08AkYN0OSXykC6+2r4=";
    dontNpmBuild = true;
    npmFlags = ["--ignore-scripts"];
    nativeBuildInputs = [pkgs.bun];

    postInstall = ''
      mkdir -p "$out/lib"
      bun build cua-mcp-client.ts --target=bun --format=esm --outfile "$out/lib/cua-mcp-client.ts"
      rm -rf "$out/lib/node_modules"
    '';

    meta = {
      description = "Lazy official MCP SDK client for Cua Driver";
      license = pkgs.lib.licenses.mit;
      platforms = pkgs.lib.platforms.unix;
    };
  }
