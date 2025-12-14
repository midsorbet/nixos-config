{ config, pkgs, lib, ... }:

let
  user = "me";
  xdg_configHome  = "/home/${user}/.config";
  shared-programs = import ../shared/home-manager.nix { inherit config pkgs lib; };
  shared-files = import ../shared/files.nix { inherit config pkgs; };

in
{
  home = {
    username = "${user}";
    homeDirectory = "/home/${user}";
    packages = pkgs.callPackage ./packages.nix {};
    file = shared-files // import ./files.nix { inherit user; };
    stateVersion = "25.11";
  };


  services = {
    # Auto mount devices
    udiskie.enable = true;
  };

  programs = shared-programs // { gpg.enable = true; };

}
