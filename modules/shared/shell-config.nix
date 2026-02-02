{
  pkgs,
  lib,
  ...
}: let
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
in {
  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    zsh = {
      enable = true;
      interactiveShellInit = lib.mkBefore ''
        if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
          . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
          . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
        fi

        typeset -U cdpath
        cdpath=(~/Projects)

        eval "$(${pkgs.oh-my-posh}/bin/oh-my-posh init zsh --config ${ohMyPoshConfig})"
      '';
    };
  };
}
