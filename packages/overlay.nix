{
  inputs,
  aggregate ? true,
}: let
  overlays = {
    apyanki = final: prev: {
      apyanki = final.callPackage ./apyanki.nix {inherit inputs;};
    };

    github-copilot-cli = final: prev: {
      github-copilot-cli = import ./github-copilot-cli.nix {pkgs = prev;};
    };

    mdfried = final: prev: {
      mdfried = final.callPackage ./mdfried.nix {
        mdfriedInput = inputs.mdfried;
      };
    };

    hister = final: prev: {
      hister = final.callPackage ./hister.nix {};
    };

    omp = final: prev: {
      omp = import ./omp.nix {pkgs = prev;};
    };

    plannotator = final: prev: {
      plannotator = import ./plannotator.nix {pkgs = prev;};
    };

    trzsz-go = final: prev: {
      trzsz-go = final.callPackage ./trzsz-go.nix {};
    };
  };

  overlayList = [
    overlays.apyanki
    overlays.github-copilot-cli
    overlays.mdfried
    overlays.hister
    overlays.omp
    overlays.plannotator
    overlays.trzsz-go
  ];

  aggregateOverlay = final: prev:
    builtins.foldl' (acc: overlay: acc // overlay final prev) {} overlayList;
in
  if aggregate
  then aggregateOverlay
  else overlays
