{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
in
  shared-packages
  ++ [
    aube
    fswatch
    gh
    neovim
    uv
  ]
