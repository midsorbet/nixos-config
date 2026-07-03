{
  inputs,
  aggregate ? true,
}: let
  overlays = {
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

    awscli2 = final: prev: {
      awscli2 = import ./awscli2.nix {pkgs = prev;};
    };

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

    omp = final: prev: {
      omp = import ./omp.nix {pkgs = prev;};
    };

    plannotator = final: prev: {
      plannotator = import ./plannotator.nix {pkgs = prev;};
    };

    omp-collab = final: prev: import ./omp-collab-tunnel {pkgs = prev;};

    tsshd = final: prev: {
      tsshd = prev.tsshd.overrideAttrs (_: {
        version = "0.1.8";
        src = prev.fetchFromGitHub {
          owner = "trzsz";
          repo = "tsshd";
          tag = "v0.1.8";
          hash = "sha256-YqSSJA/jP8WRbfwC5fxFE4su01ZEPQNmiNRr96pDE1g=";
        };
        vendorHash = "sha256-HJWxphZuBh3gXPoEqL/EVGtwdWyW+cMSQhKyfSymKG0=";
      });
    };

    trzsz-go = final: prev: {
      trzsz-go = final.callPackage ./trzsz-go.nix {};
    };

    zmx = final: prev: import ./zmx {inherit inputs;} final prev;
  };

  overlayList = [
    overlays.direnv
    overlays.awscli2
    overlays.apyanki
    overlays.github-copilot-cli
    overlays.mdfried
    overlays.omp
    overlays.omp-collab
    overlays.plannotator
    overlays.tsshd
    overlays.trzsz-go
    overlays.zmx
  ];

  aggregateOverlay = final: prev:
    builtins.foldl' (acc: overlay: acc // overlay final prev) {} overlayList;
in
  if aggregate
  then aggregateOverlay
  else overlays
