{pkgs}:
with pkgs; let
  shared-packages = import ../../modules/shared/packages.nix {inherit pkgs;};
in
  shared-packages
  ++ [
    ghostty
    inetutils
    inotify-tools
    keepassxc
    libnotify
    sbctl
    smartmontools
    tree
    unixtools.ifconfig
    unixtools.netstat
    usbutils
    xdg-utils
  ]
