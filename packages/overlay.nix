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
        specialArgs = {
          gitCommitSigning = {
            enable = false;
            keyPath = "~/.ssh/id_github.pub";
          };
          gitPager = null;
        };
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

    readeck = final: prev: {
      readeck = final.callPackage ./readeck.nix {};
    };

    tsshd = final: prev: {
      tsshd = prev.tsshd.overrideAttrs (_: {
        version = "0.1.7";
        src = prev.fetchFromGitHub {
          owner = "trzsz";
          repo = "tsshd";
          tag = "v0.1.7";
          hash = "sha256-9llfXzAAQgAOeaD+o3AVyhP0uL88uQsCNlqAPNfzDVw=";
        };
        vendorHash = "sha256-btTWkuLkT2e58TYqe0e/cE/0Try/g8XoahiABSSFaGU=";
      });
    };

    trzsz-go = final: prev: {
      trzsz-go = final.callPackage ./trzsz-go.nix {};
    };

    zmx = final: prev: import ./zmx {inherit inputs;} final prev;
  };

  overlayList = [
    overlays.zsh
    overlays.wrapperPackages
    overlays.direnv
    overlays.awscli2
    overlays.apyanki
    overlays.github-copilot-cli
    overlays.mdfried
    overlays.readeck
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
