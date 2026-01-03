{
  pkgs,
  config,
  ...
}: let
  githubPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMwA2ciZPW8ithoSMHHbABLqjsKVW08c5tg6+lJEYipi";
in {
  ".ssh/id_github.pub" = {
    text = githubPublicKey;
  };
}
