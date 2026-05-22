{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.anki;
  jsonFormat = pkgs.formats.json {};

  homeDir = "/Users/${cfg.user}";
  ankiBasePath = "${homeDir}/${cfg.baseDirectory}";
  ankiConnectPackage = cfg.ankiConnect.package.withConfig {
    config = cfg.ankiConnect.settings;
  };
  ankiConnectSource = "${ankiConnectPackage}/share/anki/addons/anki-connect";
  apySettings =
    {
      base_path = ankiBasePath;
      profile_name = cfg.profileName;
    }
    // cfg.apy.extraSettings;
in {
  options.local.anki = {
    enable = lib.mkEnableOption "declarative-ish Anki management for Homebrew Anki";

    user = lib.mkOption {
      type = lib.types.str;
      default = config.system.primaryUser;
      description = "User that should receive the Hjem-managed Anki add-ons and apy config.";
    };

    installHomebrewCask = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install the Homebrew Anki cask.";
    };

    homebrewCask = lib.mkOption {
      type = lib.types.str;
      default = "anki";
      description = "Homebrew cask name for the Anki application.";
    };

    baseDirectory = lib.mkOption {
      type = lib.types.str;
      default = "Library/Application Support/Anki2";
      description = "Anki base directory relative to the managed user's home.";
    };

    profileName = lib.mkOption {
      type = lib.types.str;
      default = "User 1";
      description = "Anki profile name used by apy.";
    };

    ankiConnect = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to Hjem-link AnkiConnect into the Homebrew Anki add-ons directory.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.ankiAddons.anki-connect;
        description = "AnkiConnect add-on package to link.";
      };

      addonDirectoryName = lib.mkOption {
        type = lib.types.str;
        default = "anki-connect";
        description = "Directory name under Anki's addons21 directory.";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf jsonFormat.type;
        default = {
          apiKey = null;
          apiLogPath = null;
          webBindAddress = "127.0.0.1";
          webBindPort = 8765;
          webCorsOriginList = ["http://localhost"];
          ignoreOriginList = [];
        };
        description = "AnkiConnect add-on configuration written through its Anki meta.json.";
      };
    };

    apy = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to install apyanki and write its config.";
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.apyanki;
        description = "apyanki package to install.";
      };

      extraSettings = lib.mkOption {
        type = lib.types.attrsOf jsonFormat.type;
        default = {};
        description = "Additional settings merged into ~/.config/apy/apy.json.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(lib.hasPrefix "/" cfg.baseDirectory);
        message = "local.anki.baseDirectory must be relative to the managed user's home.";
      }
    ];

    homebrew.casks = lib.mkIf cfg.installHomebrewCask [cfg.homebrewCask];

    hjem.users.${cfg.user} = {
      packages = lib.optionals cfg.apy.enable [cfg.apy.package];

      files."${cfg.baseDirectory}/addons21/${cfg.ankiConnect.addonDirectoryName}" =
        lib.mkIf cfg.ankiConnect.enable
        {
          type = "symlink";
          source = ankiConnectSource;
          clobber = true;
        };

      xdg.config.files."apy/apy.json" = lib.mkIf cfg.apy.enable {
        source = jsonFormat.generate "apy.json" apySettings;
        clobber = true;
      };
    };
  };
}
