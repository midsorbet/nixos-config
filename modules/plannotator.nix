{
  config,
  lib,
  pkgs,
  ...
}: {
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

  config = lib.mkIf config.local.plannotator.enable {
    hjem.users.${config.local.plannotator.user}.packages = [config.local.plannotator.package];
  };
}
