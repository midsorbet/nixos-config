{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.zsh;

  baseOhMyPoshConfig = builtins.fromJSON (
    builtins.unsafeDiscardStringContext (
      builtins.readFile "${pkgs.oh-my-posh}/share/oh-my-posh/themes/catppuccin_frappe.omp.json"
    )
  );

  zmxBlock = {
    type = "prompt";
    alignment = "left";
    segments = [
      {
        type = "text";
        style = "plain";
        foreground = "p:mauve";
        template = "{{ if .Env.ZMX_SESSION }} {{ .Env.ZMX_SESSION }} {{ end }}";
      }
    ];
  };

  mkOhMyPoshConfig = palette:
    baseOhMyPoshConfig
    // {
      inherit palette;
      blocks = [zmxBlock] ++ baseOhMyPoshConfig.blocks;
    };

  catppuccinFrappeConfig = pkgs.writeText "oh-my-posh-catppuccin-frappe.json" (
    builtins.toJSON (mkOhMyPoshConfig baseOhMyPoshConfig.palette)
  );

  kanagawaWaveConfig = pkgs.writeText "oh-my-posh-kanagawa-wave.json" (
    builtins.toJSON (mkOhMyPoshConfig {
      os = "#727169";
      closer = "p:os";
      pink = "#957fb8";
      mauve = "#957fb8";
      lavender = "#7fb4ca";
      blue = "#7e9cd8";
    })
  );

  everforestLightHardConfig = pkgs.writeText "oh-my-posh-everforest-light-hard.json" (
    builtins.toJSON (mkOhMyPoshConfig {
      os = "#a6b0a0";
      closer = "p:os";
      pink = "#d699b6";
      mauve = "#d699b6";
      lavender = "#3a94c5";
      blue = "#7fbbb3";
    })
  );

  ohMyPoshInit =
    if cfg.promptTheme == "kanagawa-everforest"
    then ''
      oh_my_posh_config=${kanagawaWaveConfig}
      if [[ "$(uname -s)" == "Darwin" ]] && command -v defaults >/dev/null 2>&1; then
        if ! defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
          oh_my_posh_config=${everforestLightHardConfig}
        fi
      fi
      eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config "$oh_my_posh_config")"
    ''
    else ''
      eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config ${catppuccinFrappeConfig})"
    '';

  zshrc = ''
    # Managed by Nix/Hjem.
    if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
      . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
      . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
    fi

    typeset -U path cdpath
    setopt hist_verify

    # Prefer the system profile, but keep NixOS privilege wrappers first.
    [[ -d /run/current-system/sw/bin ]] && path=(/run/current-system/sw/bin $path)
    [[ -d /run/wrappers/bin ]] && path=(/run/wrappers/bin $path)
    cdpath=(${lib.concatStringsSep " " cfg.projectDirectories})

    if command -v zmx >/dev/null 2>&1; then
      eval "$(zmx completions zsh)"
    fi

    ${ohMyPoshInit}
  '';
in {
  options.local.zsh = {
    enable = lib.mkEnableOption "Hjem-managed zsh defaults";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed zsh config.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zsh;
      description = "zsh package to install and use as the user's shell.";
    };

    projectDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["~/Projects"];
      description = "Directories zsh should search when changing into project names.";
    };

    promptTheme = lib.mkOption {
      type = lib.types.enum ["catppuccin-frappe" "kanagawa-everforest"];
      default = "catppuccin-frappe";
      description = "Oh My Posh prompt color theme.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.enable = true;
    environment.shells = [cfg.package];
    environment.systemPackages = [cfg.package];

    users.users.${cfg.user}.shell = cfg.package;

    hjem.users.${cfg.user}.files.".zshrc" = {
      text = zshrc;
      clobber = true;
    };
  };
}
