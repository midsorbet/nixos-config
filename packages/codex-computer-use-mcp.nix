{pkgs}: let
  version = "0.4.0";
  sourceSrc = pkgs.fetchFromGitHub {
    owner = "tmustier";
    repo = "codex-computer-use-mcp";
    tag = "v${version}";
    hash = "sha256-FN9u7cfK2/gDPHvzmspSdeoD3Ry6wI4dfVzELdcClEc=";
  };
in
  pkgs.buildNpmPackage {
    pname = "codex-computer-use-mcp";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://registry.npmjs.org/codex-computer-use-mcp/-/codex-computer-use-mcp-${version}.tgz";
      hash = "sha256-6PNeB0QcZJA3FMr3UDsHCKJskxEE2DPnal683wCgDw0=";
    };
    sourceRoot = "package";

    npmDepsHash = "sha256-GkHGN7oOm9X3V1SAmlIkoQUQTbSq9bAZ3scHjOHAbAs=";
    prePatch = ''
      cp ${sourceSrc}/package-lock.json package-lock.json
    '';
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
      ' package-lock.json >package-lock.pruned.json
      mv package-lock.pruned.json package-lock.json
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
