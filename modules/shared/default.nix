{
  lib,
  pkgs,
  ...
}: {
  imports = [
    ./wrapper-manager.nix
  ];

  environment.shells = [pkgs.wrapperPackages.zsh];
  environment.interactiveShellInit = lib.mkBefore ''
    zms() {
      if [ -x "${pkgs.zmx-select}/bin/zmx-select" ]; then
        PATH="${pkgs.zmx}/bin:$PATH" ${pkgs.zmx-select}/bin/zmx-select "$@"
      fi
    }

    if [ -z "''${ZMX_SESSION-}" ] \
      && [ -t 0 ] \
      && [ -t 1 ]; then
      case "$0" in
        -*)
          zms && exit
          ;;
      esac
    fi
  '';

  programs = {
    direnv = {
      enable = true;
      nix-direnv.enable = true;
    };

    zsh = {
      enable = true;
    };
  };
}
