{
  config,
  pkgs,
  agenix,
  secrets,
  ...
}: let
  user = "me";
in {
  age.identityPaths = [
    "/etc/ssh/ssh_host_ed25519_key"
  ];

  age.secrets."github-ssh-key" = {
    symlink = false;
    path = "/home/${user}/.ssh/id_github";
    file = "${secrets}/github-ssh-key.age";
    mode = "600";
    owner = "${user}";
    group = "wheel";
  };

  age.secrets."readeck-env" = {
    file = "${secrets}/readeck.age";
  };
}
