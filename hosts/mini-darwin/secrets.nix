{secrets, ...}: let
  user = "me";
in {
  age.identityPaths = [
    "/Users/${user}/.ssh/id_ed25519"
  ];

  age.secrets."user-email".file = "${secrets}/user-email.age";

  age.secrets."github-ssh-key" = {
    symlink = true;
    path = "/Users/${user}/.ssh/id_github";
    file = "${secrets}/github-ssh-key.age";
    mode = "600";
    owner = "${user}";
    group = "staff";
  };

  age.secrets."baymax-builder-ssh-key" = {
    symlink = false;
    path = "/etc/nix/baymax-builder-ed25519";
    file = "${secrets}/baymax-builder-ssh-key.age";
    mode = "600";
    owner = "root";
    group = "wheel";
  };

  # age.secrets."github-signing-key" = {
  #   symlink = false;
  #   path = "/Users/${user}/.ssh/pgp_github.key";
  #   file =  "${secrets}/github-signing-key.age";
  #   mode = "600";
  #   owner = "${user}";
  # };
}
