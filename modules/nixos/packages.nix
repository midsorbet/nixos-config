{pkgs}:
with pkgs; let
  shared-packages = import ../shared/packages.nix {inherit pkgs;};
in
  shared-packages
  ++ [
    ghostty

    # Security and authentication
    keepassxc

    # App and package management
    gnumake
    cmake
    home-manager

    # Text and terminal utilities
    tree
    unixtools.ifconfig
    unixtools.netstat

    # File and system utilities
    inotify-tools # inotifywait, inotifywatch - For file system events
    libnotify
    xdg-utils
  ]
