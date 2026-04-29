{
  inputs,
  aggregate ? true,
}: let
  nixpkgsMasterFor = system:
    import inputs.nixpkgs-master {
      inherit system;
    };

  overlays = {
    zsh = final: prev:
      prev.lib.optionalAttrs prev.stdenv.isDarwin {
        zsh = (nixpkgsMasterFor prev.stdenv.hostPlatform.system).zsh;
      };

    wrapperPackages = final: prev: let
      evald = inputs.wrapper-manager.lib {
        pkgs = final;
        modules = let
          entries = builtins.readDir ../modules/wrapper-manager;
        in
          map (name: ../modules/wrapper-manager/${name}) (builtins.attrNames entries);
      };
    in {
      wrapperPackages = builtins.mapAttrs (_: value: value.wrapped) evald.config.wrappers;
    };

    direnv = final: prev: {
      direnv = prev.direnv.overrideAttrs (_:
        prev.lib.optionalAttrs prev.stdenv.isDarwin {
          # The zsh in current nixos-unstable hangs during direnv's zsh check on Darwin.
          nativeCheckInputs = [
            prev.fish
            final.zsh
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
    overlays.zsh
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
