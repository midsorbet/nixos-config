{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
  frog = import ../../packages/frog {inherit pkgs;};
in
  shared-packages
  ++ [
    aube
    frog
    fswatch
    gh
    neovim
    uv
  ]
