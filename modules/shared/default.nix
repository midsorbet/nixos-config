{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./wrapper-manager.nix
  ];

  environment.shells = [pkgs.zsh-wrapped];

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
