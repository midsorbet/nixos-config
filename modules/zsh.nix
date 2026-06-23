{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.zsh;

  ohMyPoshConfig = let
    base = builtins.fromJSON (
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
    merged = base // {blocks = [zmxBlock] ++ base.blocks;};
  in
    pkgs.writeText "oh-my-posh.json" (builtins.toJSON merged);

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

    eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config ${ohMyPoshConfig})"
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
