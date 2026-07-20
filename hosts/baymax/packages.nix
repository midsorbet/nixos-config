{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
in
  shared-packages
  ++ [
    (import ../../packages/codex.nix {inherit pkgs;})
    ghostty
    inetutils
    inotify-tools
    keepassxc
    omp
    libnotify
    sbctl
    smartmontools
    tree
    unixtools.ifconfig
    unixtools.netstat
    usbutils
    xdg-utils
  ]
