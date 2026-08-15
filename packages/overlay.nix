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

    libmamba = _final: prev: {
      libmamba = prev.libmamba.overrideAttrs (old: {
        patches =
          (old.patches or [])
          ++ [
            (prev.fetchpatch {
              url = "https://github.com/mamba-org/mamba/commit/792c6efb644fa063c9c76f2d9d6bebd5589e743f.patch";
              hash = "sha256-kKMOfT6e/lO9+mf9pbqVNBKNXVP7+1wvME8Kq24R914=";
            })
          ];
      });
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

    tsshd = final: prev: {
      tsshd = prev.tsshd.overrideAttrs (_: {
        version = "0.1.9";
        src = prev.fetchFromGitHub {
          owner = "trzsz";
          repo = "tsshd";
          tag = "v0.1.9";
          hash = "sha256-/h18WuKkPWD5sDvLckQPcL7f5VG2dlD6uGheUrwMXFQ=";
        };
        vendorHash = "sha256-+hX81OgNBNs85c51WXSsIBMClRTvsmmiVdvQtV5ml2g=";
      });
    };

    trzsz-go = final: prev: {
      trzsz-go = final.callPackage ./trzsz-go.nix {};
    };

    zmx = final: prev: import ./zmx {} final prev;
  };

  overlayList = [
    overlays.direnv
    overlays.libmamba
    overlays.apyanki
    overlays.github-copilot-cli
    overlays.mdfried
    overlays.omp
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
