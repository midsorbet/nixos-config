{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.ghostty;
  lightThemeName = "everforest-light-hard";
  darkThemeName = "kanagawa-wave";

  configText = ''
    theme = light:${lightThemeName},dark:${darkThemeName}
    font-family = "${cfg.fontFamily}"
    font-size = ${toString cfg.fontSize}
    copy-on-select = "clipboard"
    cursor-style-blink = false
    window-save-state = never
    keybind = shift+enter=text:\x1b\r
  '';

  themes = {
    "everforest-light-hard" = ''
      palette = 0=#7a8478
      palette = 1=#e67e80
      palette = 2=#9ab373
      palette = 3=#ceaf72
      palette = 4=#7fbbb3
      palette = 5=#d699b6
      palette = 6=#83c092
      palette = 7=#b2af9f
      palette = 8=#a6b0a0
      palette = 9=#f85552
      palette = 10=#8da101
      palette = 11=#dfa000
      palette = 12=#3a94c5
      palette = 13=#df69ba
      palette = 14=#35a77c
      palette = 15=#fffbef

      background = #f2efdf
      foreground = #5c6a72
      cursor-color = #f57d26
      selection-background = #f0f2d4
      selection-foreground = #5c6a72
    '';

    "kanagawa-wave" = ''
      palette = 0=#090618
      palette = 1=#c34043
      palette = 2=#76946a
      palette = 3=#c0a36e
      palette = 4=#7e9cd8
      palette = 5=#957fb8
      palette = 6=#6a9589
      palette = 7=#c8c093
      palette = 8=#727169
      palette = 9=#e82424
      palette = 10=#98bb6c
      palette = 11=#e6c384
      palette = 12=#7fb4ca
      palette = 13=#938aa9
      palette = 14=#7aa89f
      palette = 15=#dcd7ba

      background = #1f1f28
      foreground = #dcd7ba
      cursor-color = #dcd7ba
      selection-background = #dcd7ba
      selection-foreground = #1f1f28
    '';
  };
in {
  options.local.ghostty = {
    enable = lib.mkEnableOption "Ghostty configuration";

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
  };

  config = lib.mkIf cfg.enable {
    fonts.packages = [cfg.fontPackage];

    hjem.users.${cfg.user} = {
      inherit (cfg) directory user;

      xdg.config.files =
        {
          "ghostty/config" = {
            text = configText;
            clobber = true;
          };
        }
        // (lib.mapAttrs' (name: text:
          lib.nameValuePair "ghostty/themes/${name}" {
            inherit text;
            clobber = true;
          })
        themes);
    };
  };
}
