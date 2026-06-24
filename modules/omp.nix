{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.omp;

  assetSrc = pkgs.fetchzip {
    url = "https://github.com/can1357/oh-my-pi/archive/refs/tags/v${cfg.package.version}.tar.gz";
    hash = "sha256-ljuQCYEN0m1UkP130gqPoipCwyHWeR3a0r9ekkOw+u4=";
  };
  runtimePath = lib.makeBinPath ([cfg.pythonPackage cfg.bunPackage cfg.uvPackage] ++ cfg.extraRuntimePackages);

  wrappedPackage =
    pkgs.runCommand "omp-${cfg.package.version}-with-runtimes" {
      nativeBuildInputs = [pkgs.makeWrapper];
    } ''
      mkdir -p "$out/bin"

      mkdir -p "$out/share"
      cp -R ${cfg.package}/share/. "$out/share/"
      mkdir -p "$out/share/omp"
      cp -R ${assetSrc}/docs "$out/share/omp/docs"
      cp -R ${assetSrc}/packages/coding-agent/examples "$out/share/omp/examples"
      cp ${assetSrc}/packages/coding-agent/CHANGELOG.md "$out/share/omp/CHANGELOG.md"
      cp ${assetSrc}/packages/coding-agent/README.md "$out/share/omp/README.md"

      makeWrapper ${lib.getExe cfg.package} "$out/bin/omp" \
        --prefix PATH : ${lib.escapeShellArg runtimePath} \
        --set-default PI_PY 1 \
        --set-default PI_JS 1 \
        --set-default PI_PACKAGE_DIR "$out/share/omp"
    '';
in {
  options.local.omp = {
    enable = lib.mkEnableOption "global OMP with Nix-provided eval runtimes";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omp;
      description = "OMP package to wrap and install.";
    };

    pythonPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.python313;
      description = "Python interpreter made available to OMP eval cells.";
    };

    bunPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.bun;
      description = "Bun runtime made available to OMP and its tool subprocesses.";
    };

    uvPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.uv;
      description = "uv package manager made available to OMP and its tool subprocesses.";
    };

    extraRuntimePackages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [];
      description = "Additional packages to prepend to PATH for OMP runtime and tool subprocesses.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [wrappedPackage];
  };
}
