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
    if [ -z "''${ZMX_SESSION-}" ] \
      && [ -x "${pkgs.zmx}/bin/zmx-select" ]; then
      ${pkgs.zmx}/bin/zmx-select && exit
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
