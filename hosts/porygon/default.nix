let
  user = "me";
  # Fill this with the dedicated delcatty-to-porygon public key.
  delcattyKey = "";
in {
  imports = [
    ../../modules/github-cli.nix
    ../../modules/hunk.nix
    ../../modules/nixos/wsl-dev.nix
  ];

  networking.hostName = "porygon";
  system.stateVersion = "26.05";

  local.wslDev = {
    enable = true;
    inherit user;
    enableSshServer = true;
    authorizedKeys =
      if delcattyKey == ""
      then []
      else [delcattyKey];
  };

  local.githubCli = {
    enable = true;
    inherit user;
  };
  local.hunk = {
    enable = true;
    inherit user;
  };
}
