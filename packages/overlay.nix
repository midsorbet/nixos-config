{
  inputs,
  aggregate ? true,
}: let
  overlays = {
    wrapperPackages = final: prev: let
      evald = inputs.wrapper-manager.lib {
        pkgs = prev;
        modules = let
          entries = builtins.readDir ../modules/wrapper-manager;
        in
          map (name: ../modules/wrapper-manager/${name}) (builtins.attrNames entries);
      };
    in {
      wrapperPackages = builtins.mapAttrs (_: value: value.wrapped) evald.config.wrappers;
    };

    direnv = final: prev: let
      nixpkgsMaster = import inputs.nixpkgs-master {
        system = prev.stdenv.hostPlatform.system;
      };
    in {
      direnv = prev.direnv.overrideAttrs (_:
        prev.lib.optionalAttrs prev.stdenv.isDarwin {
          # The zsh in current nixos-unstable hangs during direnv's zsh check on Darwin.
          nativeCheckInputs = [
            prev.fish
            nixpkgsMaster.zsh
            prev.writableTmpDirAsHomeHook
          ];
        });
    };

    mdfried = final: prev: {
      mdfried = final.callPackage ./mdfried.nix {
        mdfriedInput = inputs.mdfried;
      };
    };

    readeck = final: prev: {
      readeck = final.callPackage ./readeck.nix {};
    };

    zmx = final: prev: import ./zmx {inherit inputs;} final prev;
  };

  overlayList = [
    overlays.wrapperPackages
    overlays.direnv
    overlays.mdfried
    overlays.readeck
    overlays.zmx
  ];

  aggregateOverlay = final: prev:
    builtins.foldl' (acc: overlay: acc // overlay final prev) {} overlayList;
in
  if aggregate
  then aggregateOverlay
  else overlays
