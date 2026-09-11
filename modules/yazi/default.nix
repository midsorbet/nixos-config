{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.yazi;

  # Plugins are symlinked from nixpkgs into ~/.config/yazi/plugins so that
  # keymap.toml and init.lua can reference them by name without `ya pkg`.
  plugins = {
    inherit
      (pkgs.yaziPlugins)
      chmod
      full-border
      git
      jump-to-char
      smart-enter
      toggle-pane
      ;
  };

  # Flavors follow the Ghostty theme pair: kanagawa-wave for dark and
  # everforest-light-hard for light. Yazi picks one from theme.toml's
  # [flavor] table based on the terminal background.
  flavors = {
    kanagawa = pkgs.yaziPlugins.kanagawa;
    everforest-light-hard = ./flavors/everforest-light-hard.yazi;
  };

  mkSymlinks = subdir:
    lib.mapAttrs' (name: source:
      lib.nameValuePair "yazi/${subdir}/${name}.yazi" {
        type = "symlink";
        inherit source;
        clobber = true;
      });

  configFiles = lib.listToAttrs (map (name:
    lib.nameValuePair "yazi/${name}" {
      source = ./. + "/${name}";
      clobber = true;
    }) ["yazi.toml" "keymap.toml" "theme.toml" "init.lua"]);

  # Upstream shell wrapper: https://yazi-rs.github.io/docs/quick-start#shell-wrapper
  shellWrapper = ''
    # yazi: `y` changes the shell's directory to where Yazi was quit (q); Q keeps it.
    function y() {
      local tmp cwd; tmp="$(mktemp -t "yazi-cwd.XXXXXX")"
      ${lib.getExe cfg.package} "$@" --cwd-file="$tmp"
      IFS= read -r -d "" cwd < "$tmp"
      [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd" || builtin true
      command rm -f -- "$tmp"
    }
  '';
in {
  options.local.yazi = {
    enable = lib.mkEnableOption "Hjem-managed Yazi file manager";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should own the Hjem-managed Yazi files.";
    };

    directory = lib.mkOption {
      type = lib.types.path;
      default =
        if pkgs.stdenv.isDarwin
        then "/Users/${cfg.user}"
        else "/home/${cfg.user}";
      description = "Home directory for the user managed by Hjem.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.yazi;
      description = "Yazi package providing the `yazi` and `ya` binaries.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.interactiveShellInit = shellWrapper;

    hjem.users.${cfg.user} = {
      inherit (cfg) directory user;
      packages = [cfg.package];

      xdg.config.files =
        configFiles
        // mkSymlinks "plugins" plugins
        // mkSymlinks "flavors" flavors;
    };
  };
}
