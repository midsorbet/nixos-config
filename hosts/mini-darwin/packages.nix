{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
  frog = import ../../packages/frog {inherit pkgs;};
  rem = import ../../packages/rem.nix {inherit pkgs;};
in
  shared-packages
  ++ [
    aube
    frog
    fswatch
    gh
    rem
    uv
  ]
