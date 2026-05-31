{...}: {
  imports = [
    ../git.nix
    ../zsh.nix
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
