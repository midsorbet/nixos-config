{lib, ...}: let
  # Fill this with the HP Windows hostname or IP that forwards SSH to Porygon.
  porygonSshHost = "";
  porygonSshPort = 22;
  porygonSshUser = "me";
  porygonIdentityFile = "/home/nixos/.ssh/id_delcatty_porygon";
in {
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

  programs.ssh.extraConfig = lib.optionalString (porygonSshHost != "") ''
    Host porygon
      HostName ${porygonSshHost}
      Port ${toString porygonSshPort}
      User ${porygonSshUser}
      IdentityFile ${porygonIdentityFile}
      IdentitiesOnly yes

      #!! EnableTrzsz Yes
      #!! EnableDragFile Yes
      #!! DragFileUploadCommand trz -y
  '';
}
