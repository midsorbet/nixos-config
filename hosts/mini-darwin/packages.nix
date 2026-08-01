{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
  pdf-inspector = pkgs.callPackage ../../packages/pdf-inspector.nix {};
in
  shared-packages
  ++ [
    aube
    fswatch
    gh
    neovim
    pdf-inspector
    uv
  ]
