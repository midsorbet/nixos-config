{
  config,
  hunk,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.hunk;
  tomlFormat = pkgs.formats.toml {};
  defaultPackage = hunk.packages.${pkgs.stdenv.hostPlatform.system}.hunk.overrideAttrs (old: {
    postInstall =
      (old.postInstall or "")
      + lib.optionalString pkgs.stdenv.isDarwin ''
        /usr/bin/codesign --force --sign - "$out/bin/hunk"
      '';
  });
in {
  options.local.hunk = {
    enable = lib.mkEnableOption "Hunk terminal diff viewer";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed Hunk package and config.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "Hunk package to install.";
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {
        theme = "auto";
        mode = "auto";
        line_numbers = true;
        wrap_lines = true;
        agent_notes = true;
        transparent_background = true;
      };
      description = "Hunk TOML configuration written to the user's XDG config directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user} = {
      packages = [cfg.package];

      xdg.config.files."hunk/config.toml" = lib.mkIf (cfg.settings != {}) {
        source = tomlFormat.generate "hunk-config.toml" cfg.settings;
        clobber = true;
      };
    };
  };
}
