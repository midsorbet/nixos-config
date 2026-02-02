{
  pkgs,
  wrapper-manager,
  ...
}: let
  wrapperManager = wrapper-manager.lib {
    inherit pkgs;
    modules = let
      entries = builtins.readDir ../wrapper-manager;
    in
      map (name: ../wrapper-manager/${name}) (builtins.attrNames entries);
  };
in {
  environment.systemPackages = builtins.attrValues wrapperManager.config.build.packages;
}
