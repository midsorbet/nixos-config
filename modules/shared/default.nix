{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./wrapper-manager.nix
  ];

  environment.shells = [pkgs.wrapperPackages.zsh];

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
