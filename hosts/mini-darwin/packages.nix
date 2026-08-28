{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
  frog = import ../../packages/frog {inherit pkgs;};
  remindctl = import ../../packages/remindctl.nix {inherit pkgs;};
  seedsCli = import ../../packages/seeds-cli.nix {inherit pkgs;};
in
  shared-packages
  ++ [
    aube
    frog
    fswatch
    gh
    remindctl
    seedsCli
    uv
  ]
