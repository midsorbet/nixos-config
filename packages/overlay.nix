{inputs}: final: prev: let
  wrapper-manager = inputs.wrapper-manager;
  evald = wrapper-manager.lib {
    pkgs = prev;
    modules = let
      entries = builtins.readDir ../modules/wrapper-manager;
    in
      map (name: ../modules/wrapper-manager/${name}) (builtins.attrNames entries);
  };
  wrapperPackages = builtins.mapAttrs (_: value: value.wrapped) evald.config.wrappers;
  system = final.stdenv.hostPlatform.system;
  localZmx = final.callPackage ./zmx {};
in {
  wrapperPackages = wrapperPackages;
  readeck = final.callPackage ./readeck.nix {};
  zmx = inputs.zmx.packages.${system}.zmx or localZmx.zmx;
  zmx-select = localZmx.zmx-select;
}
