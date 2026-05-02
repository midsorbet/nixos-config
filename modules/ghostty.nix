{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.ghostty.usgc;

  configText = ''
    theme = ${cfg.themeName}
    font-family = "${cfg.fontFamily}"
    font-size = ${toString cfg.fontSize}
    keybind = shift+enter=text:\x1b\r
  '';

  # Ported from U.S. Graphics Company's USGC-POLYIMIDE-ST Sublime Text theme:
  # https://github.com/usgraphics/usgc-themes/blob/master/themes/sublime-text/USGC-POLYIMIDE-ST.sublime-color-scheme
  themeText = ''
    background = #000000
    foreground = #FFBF00
    cursor-color = #00A645
    selection-background = #000066
    selection-foreground = #00FFFF

    palette = 0=#000000
    palette = 1=#660000
    palette = 2=#00A645
    palette = 3=#FFBF00
    palette = 4=#000066
    palette = 5=#660066
    palette = 6=#006666
    palette = 7=#999999
    palette = 8=#666600
    palette = 9=#FF0000
    palette = 10=#00FF00
    palette = 11=#FFFF00
    palette = 12=#0000FF
    palette = 13=#FF00FF
    palette = 14=#00FFFF
    palette = 15=#FFFFFF
  '';
in {
  options.local.ghostty.usgc = {
    enable = lib.mkEnableOption "USGC-themed Ghostty configuration";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should own the Hjem-managed Ghostty files.";
    };

    directory = lib.mkOption {
      type = lib.types.path;
      default =
        if pkgs.stdenv.isDarwin
        then "/Users/${cfg.user}"
        else "/home/${cfg.user}";
      description = "Home directory for the user managed by Hjem.";
    };

    fontPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.maple-mono.NF;
      description = "Font package to install for Ghostty.";
    };

    fontFamily = lib.mkOption {
      type = lib.types.str;
      default = "Maple Mono NF";
      description = "Font family name written to Ghostty's config.";
    };

    fontSize = lib.mkOption {
      type = with lib.types; either int float;
      default = 15;
      description = "Font size written to Ghostty's config.";
    };

    themeName = lib.mkOption {
      type = lib.types.str;
      default = "USGC-POLYIMIDE-ST";
      description = "Name of the managed Ghostty theme.";
    };
  };

  config = lib.mkIf cfg.enable {
    fonts.packages = [cfg.fontPackage];

    hjem.users.${cfg.user} = {
      inherit (cfg) directory user;

      xdg.config.files = {
        "ghostty/config" = {
          text = configText;
          clobber = true;
        };

        "ghostty/themes/${cfg.themeName}" = {
          text = themeText;
          clobber = true;
        };
      };
    };
  };
}
