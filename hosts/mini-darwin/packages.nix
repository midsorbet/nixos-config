{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
  pdf-inspector = pkgs.callPackage ../../packages/pdf-inspector.nix {};
  frog = import ../../packages/frog {inherit pkgs;};
in
  shared-packages
  ++ [
    aube
    frog
    fswatch
    gh
    neovim
    pdf-inspector
    uv
  ]
