{pkgs}: let
  version = "0.3.4";
in
  pkgs.buildNpmPackage {
    pname = "codex-computer-use-mcp";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/codex-computer-use-mcp/-/codex-computer-use-mcp-${version}.tgz";
      hash = "sha256-PH2lA661Y6Rt+HDnkGzDwIAN1KZcsBeRpcC6/ddBLCw=";
    };
    sourceRoot = "package";

    npmDepsHash = "sha256-xaBPKf6kW6RKOxOeJoyM/XVAHnB/zkjd8/SB8kD3Z5w=";
    postPatch = ''
      ${pkgs.lib.getExe pkgs.jq} '
        del(
          .packages[""].devDependencies,
          .packages[""].peerDependencies,
          .packages[""].peerDependenciesMeta
        )
        | .packages |= with_entries(
            select(.key == "" or ((.value.dev // false) | not))
          )
      ' npm-shrinkwrap.json >npm-shrinkwrap.pruned.json
      mv npm-shrinkwrap.pruned.json npm-shrinkwrap.json
      ${pkgs.lib.getExe pkgs.jq} '
        del(.devDependencies, .peerDependencies, .peerDependenciesMeta)
      ' package.json >package.pruned.json
      mv package.pruned.json package.json
    '';

    dontNpmBuild = true;
    npmFlags = ["--ignore-scripts" "--omit=dev"];
    meta = with pkgs.lib; {
      description = "Bridge ChatGPT's signed macOS Computer Use tools to MCP clients";
      homepage = "https://github.com/tmustier/codex-computer-use-mcp";
      license = licenses.mit;
      mainProgram = "codex-computer-use-mcp";
      platforms = platforms.darwin;
    };
  }
