{pkgs}: let
  version = "1.1.0";
in
  pkgs.buildNpmPackage {
    pname = "frog";
    inherit version;

    src = pkgs.lib.fileset.toSource {
      root = ./.;
      fileset = pkgs.lib.fileset.unions [
        ./package.json
        ./package-lock.json
      ];
    };

    npmDepsHash = "sha256-d+YLU7VZacSzzeyfJdu2z7+BEat1FH2HK3LqW1Hw3hs=";
    dontNpmBuild = true;
    npmFlags = ["--ignore-scripts"];

    postInstall = ''
      mkdir -p "$out/bin"
      ln -sf "$out/lib/node_modules/frog-wrapper/node_modules/.bin/frog" "$out/bin/frog"
    '';

    meta = {
      description = "Automated friction logging for agents";
      homepage = "https://github.com/wevm/frog";
      changelog = "https://github.com/wevm/frog/blob/main/CHANGELOG.md";
      license = pkgs.lib.licenses.mit;
      mainProgram = "frog";
    };
  }
