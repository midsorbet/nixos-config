{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.plannotator;
  piExtensionSpec = "@plannotator/pi-extension@${cfg.package.version}";
in {
  options.local.plannotator = {
    enable = lib.mkEnableOption "Plannotator plan and code review integration";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed Plannotator package.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.plannotator;
      description = "Plannotator binary package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.local.omp.enable;
        message = "local.plannotator.enable requires local.omp.enable so OMP can install the Plannotator Pi extension.";
      }
    ];

    local.omp.managedNpmPlugins = [piExtensionSpec];
    hjem.users.${cfg.user}.packages = [cfg.package];
  };
}
