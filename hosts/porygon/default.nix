let
  # Fill this with the dedicated delcatty-to-porygon public key.
  delcattyKey = "";
in {
  imports = [
    ../../modules/nixos/wsl-dev.nix
  ];

  networking.hostName = "porygon";
  system.stateVersion = "26.05";

  local.wslDev = {
    enable = true;
    user = "me";
    enableSshServer = true;
    authorizedKeys =
      if delcattyKey == ""
      then []
      else [delcattyKey];
  };
}
