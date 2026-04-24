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
      && [ -x "${pkgs.zmx-select}/bin/zmx-select" ]; then
      PATH="${pkgs.zmx}/bin:$PATH" ${pkgs.zmx-select}/bin/zmx-select && exit
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
