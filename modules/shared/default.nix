{
  config,
  pkgs,
  ...
}: {
  imports = [
    ./shell-config.nix
    ./wrapper-manager.nix
  ];

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowInsecure = false;
    };
  };
}
