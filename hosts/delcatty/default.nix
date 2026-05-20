{
  imports = [
    ../../modules/nixos/wsl-dev.nix
  ];

  networking.hostName = "delcatty";
  system.stateVersion = "25.11";

  local.wslDev = {
    enable = true;
    user = "nixos";
    flakePath = "/home/nixos/nix-config";
    enableSshServer = false;
    authorizedKeys = [];
  };
}
