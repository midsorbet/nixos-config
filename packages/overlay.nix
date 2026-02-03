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
in
  wrapperPackages
  // {
    zmx = final.callPackage ./zmx {};
  }
