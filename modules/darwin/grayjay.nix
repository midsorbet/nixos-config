{
  config,
  lib,
  ...
}: let
  cfg = config.local.grayjay;
in {
  options.local.grayjay = {
    enable = lib.mkEnableOption "Grayjay Desktop via Homebrew with mutable Hjem-managed settings";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.system.primaryUser;
      description = "User that should own the Hjem-managed Grayjay settings symlink.";
    };

    settingsFile = lib.mkOption {
      type = lib.types.str;
      default = "${config.environment.variables.NH_FLAKE}/modules/darwin/grayjay-settings.json";
      description = ''
        Absolute path string to the mutable out-of-store Grayjay settings file.
        Keep this as a string, not a Nix path literal, so Hjem links to the
        editable checkout file instead of a store copy.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix "/" cfg.settingsFile;
        message = "local.grayjay.settingsFile must be an absolute path string for Hjem's symlink manifest.";
      }
    ];

    homebrew.casks = ["grayjay"];

    hjem.users.${cfg.user}.files."Library/Application Support/Grayjay/settings.json" = {
      type = "symlink";
      source = cfg.settingsFile;
      clobber = true;
    };
  };
}
