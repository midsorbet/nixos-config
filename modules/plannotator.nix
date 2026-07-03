{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.plannotator;
  piExtensionSpec = "@plannotator/pi-extension@${cfg.package.version}";

  installPiExtensionHelper = pkgs.writeShellApplication {
    name = "plannotator-install-pi-extension";
    runtimeInputs = [cfg.ompPackage pkgs.bun];
    text = ''
      set -euo pipefail

      echo "Installing ${piExtensionSpec} into the OMP plugin directory..."
      omp install ${lib.escapeShellArg piExtensionSpec}

      echo
      echo "Installed OMP plugins:"
      omp plugin list
    '';
  };
in {
  options.local.plannotator = {
    enable = lib.mkEnableOption "Plannotator plan and code review integration";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed Plannotator package and helper.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.plannotator;
      description = "Plannotator binary package to install.";
    };

    ompPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omp;
      description = "OMP package used by the Plannotator Pi-extension install helper.";
    };

    installPiExtensionHelper = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install a helper that runs OMP's mutable npm plugin install for @plannotator/pi-extension.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user}.packages =
      [cfg.package]
      ++ lib.optional cfg.installPiExtensionHelper installPiExtensionHelper;
  };
}
