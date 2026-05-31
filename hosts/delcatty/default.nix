{lib, ...}: let
  user = "nixos";
  # Fill this with the HP Windows hostname or IP that forwards SSH to Porygon.
  porygonSshHost = "";
  porygonSshPort = 22;
  porygonSshUser = "me";
  porygonIdentityFile = "/home/${user}/.ssh/id_delcatty_porygon";
in {
  imports = [
    ../../modules/github-cli.nix
    ../../modules/hunk.nix
    ../../modules/nixos/wsl-dev.nix
  ];

  networking.hostName = "delcatty";
  system.stateVersion = "25.11";

  local.wslDev = {
    enable = true;
    inherit user;
    flakePath = "/home/${user}/nix-config";
    enableSshServer = false;
    authorizedKeys = [];
  };

  local.githubCli = {
    enable = true;
    inherit user;
  };
  local.git = {
    enable = true;
    inherit user;
  };
  local.hunk = {
    enable = true;
    inherit user;
  };
  local.zsh = {
    enable = true;
    inherit user;
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
