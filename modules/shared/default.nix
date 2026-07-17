{...}: {
  imports = [
    ../git.nix
    ../zsh.nix
  ];

  environment.variables.UV_MALWARE_CHECK = "1";

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
}
