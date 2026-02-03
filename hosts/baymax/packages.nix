{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
in
  shared-packages
  ++ [
    gitFull
    ghostty
    inetutils
    inotify-tools
    keepassxc
    libnotify
    smartmontools
    tree
    unixtools.ifconfig
    unixtools.netstat
    usbutils
    xdg-utils
  ]
