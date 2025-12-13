{ config, pkgs, ... }:
{

  nixpkgs = {
    config = {
      allowUnfree = true;
      allowInsecure = false;
    };
  };
}
