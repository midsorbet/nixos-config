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
  zmxPackages = import ./zmx {inherit inputs;} final prev;
in {
  wrapperPackages = wrapperPackages;
  mdfried = final.callPackage ./mdfried.nix {
    mdfriedInput = inputs.mdfried;
  };
  readeck = final.callPackage ./readeck.nix {};
  inherit (zmxPackages) zmx zmx-select;
}
