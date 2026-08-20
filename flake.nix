{
  description = "Starter Configuration with secrets for MacOS and NixOS";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    # Isolate Hunk's x86_64-darwin formatter and mdfried's Python 3.14 remarshal incompatibility.
    nixpkgs-darwin-compat.url = "github:nixos/nixpkgs/nixpkgs-26.05-darwin";
    # Shared agent skill revisions are pinned only by flake.lock.
    skill-agent-stuff = {
      url = "github:mitsuhiko/agent-stuff";
      flake = false;
    };
    skill-bro = {
      url = "github:backnotprop/bro";
      flake = false;
    };
    skill-diagnosing-bugs = {
      url = "github:dmmulroy/.dotfiles";
      flake = false;
    };
    skill-effective-html = {
      url = "github:plannotator/effective-html";
      flake = false;
    };
    skill-humanlayer = {
      url = "github:humanlayer/skills";
      flake = false;
    };
    skill-ideonomy = {
      url = "github:latentwill/ideonomy-skill";
      flake = false;
    };
    skill-modem = {
      url = "github:modem-dev/skills";
      flake = false;
    };
    agenix.url = "github:ryantm/agenix";
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };
    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
      inputs.uv2nix.follows = "uv2nix";
    };
    hjem = {
      url = "github:feel-co/hjem";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-wrapper-modules = {
      url = "github:BirdeeHub/nix-wrapper-modules";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    minimax = {
      url = "github:nvim-mini/MiniMax/73420d884a6117e77e6d1df4d6ca7144c8444814";
      flake = false;
    };
    hunk = {
      url = "github:modem-dev/hunk/v0.18.2";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.bun2nix.inputs.nixpkgs.follows = "nixpkgs-darwin-compat";
    };
    herdr = {
      url = "github:herdrdev/herdr/v0.8.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    herdr-omp-plugins = {
      url = "git+ssh://git@github.com/midsorbet/herdr-omp-plugins.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    paneru = {
      url = "github:karinushka/paneru/v0.4.4";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nix-darwin.follows = "darwin";
    };
    darwin = {
      url = "github:LnL7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL/main";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.1.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    secrets = {
      url = "git+ssh://git@github.com/midsorbet/nix-secrets.git";
      flake = false;
    };
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    mdfried = {
      url = "github:benjajaja/mdfried/v0.22.5";
      inputs.nixpkgs.follows = "nixpkgs-darwin-compat";
    };
  };
  outputs = {
    darwin,
    hjem,
    nix-homebrew,
    homebrew-bundle,
    homebrew-core,
    homebrew-cask,
    nixpkgs,
    disko,
    nixos-hardware,
    nixos-wsl,
    nix-index-database,
    impermanence,
    lanzaboote,
    vscode-server,
    ...
  } @ inputs: let
    user = "me";
    linuxSystems = ["x86_64-linux"];
    darwinSystems = ["aarch64-darwin"];
    forAllSystems = f: nixpkgs.lib.genAttrs (linuxSystems ++ darwinSystems) f;
    allowUnfreeNames = names: pkg: builtins.elem (nixpkgs.lib.getName pkg) names;
    allowCudaPackages = pkg: let
      licenses = nixpkgs.lib.toList (pkg.meta.license or []);
    in
      nixpkgs.lib.any (
        license: let
          fullName = license.fullName or "";
          shortName = license.shortName or "";
          spdxId = license.spdxId or "";
        in
          shortName
          == "CUDA EULA"
          || fullName == "CUDA Toolkit End User License Agreement (EULA)"
          || spdxId == "CUDA EULA"
      )
      licenses;
    devShell = system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in
      {
        default = with pkgs;
          mkShell {
            nativeBuildInputs = with pkgs; [bashInteractive git age nixd uv];
          };
      }
      // nixpkgs.lib.optionalAttrs (system == "x86_64-linux") (
        let
          wslCudaPkgs = import ./packages {
            inherit inputs system;
            config = {
              allowInsecure = false;
              allowUnfreePredicate = allowCudaPackages;
            };
          };
        in {
          wsl-cuda = with wslCudaPkgs;
            mkShell {
              nativeBuildInputs = [bashInteractive git age nixd uv];
              packages = [
                cudatoolkit
                cudaPackages.cuda_nvcc
                micromamba
              ];

              shellHook = ''
                export CUDA_PATH=${cudatoolkit}
                export LD_LIBRARY_PATH=/usr/lib/wsl/lib:/run/opengl-driver/lib''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
                echo "WSL CUDA shell ready"
                echo "CUDA_PATH=$CUDA_PATH"
              '';
            };
        }
      );
  in {
    devShells = forAllSystems devShell;
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
    overlays = import ./packages/overlay.nix {
      inherit inputs;
      aggregate = false;
    };

    darwinConfigurations = {
      mini-darwin = darwin.lib.darwinSystem {
        system = "aarch64-darwin";
        pkgs = import ./packages {
          inherit inputs;
          system = "aarch64-darwin";
          config = {
            allowUnfree = true;
            allowInsecure = false;
          };
        };
        specialArgs = inputs;
        modules = [
          hjem.darwinModules.default
          nix-index-database.darwinModules.nix-index
          {
            programs.nix-index-database.comma.enable = true;
          }
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              inherit user;
              enable = true;
              taps = {
                "homebrew/homebrew-core" = homebrew-core;
                "homebrew/homebrew-cask" = homebrew-cask;
                "homebrew/homebrew-bundle" = homebrew-bundle;
              };
              mutableTaps = false;
              autoMigrate = true;
            };
          }
          ./hosts/mini-darwin
        ];
      };
    };

    nixosConfigurations = {
      baymax = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        pkgs = import ./packages {
          inherit inputs;
          system = "x86_64-linux";
          config = {
            allowUnfreePredicate = pkg:
              builtins.elem (nixpkgs.lib.getName pkg) [
                "cloudflare-warp"
                "cloudflare-warp-headless"
              ];
          };
        };
        specialArgs = inputs;
        modules = [
          hjem.nixosModules.default
          nix-index-database.nixosModules.nix-index
          {
            programs.nix-index-database.comma.enable = true;
          }
          vscode-server.nixosModules.default
          {
            services.vscode-server.enable = true;
          }
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
          lanzaboote.nixosModules.lanzaboote
          ./hosts/baymax
        ];
      };

      flygon = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        pkgs = import ./packages {
          inherit inputs;
          system = "x86_64-linux";
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "obsidian"
              "vscode"
              "zoom"
            ];
        };
        specialArgs = inputs;
        modules = [
          hjem.nixosModules.default
          nix-index-database.nixosModules.nix-index
          {
            programs.nix-index-database.comma.enable = true;
          }
          disko.nixosModules.disko
          nixos-hardware.nixosModules.framework-13th-gen-intel
          ./hosts/flygon
        ];
      };

      porygon = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        pkgs = import ./packages {
          inherit inputs;
          system = "x86_64-linux";
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "github-copilot-cli"
            ];
        };
        specialArgs = inputs;
        modules = [
          nixos-wsl.nixosModules.default
          hjem.nixosModules.default
          nix-index-database.nixosModules.nix-index
          {
            programs.nix-index-database.comma.enable = true;
          }
          ./hosts/porygon
        ];
      };

      delcatty = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        pkgs = import ./packages {
          inherit inputs;
          system = "x86_64-linux";
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [
              "github-copilot-cli"
            ];
        };
        specialArgs = inputs;
        modules = [
          nixos-wsl.nixosModules.default
          hjem.nixosModules.default
          nix-index-database.nixosModules.nix-index
          {
            programs.nix-index-database.comma.enable = true;
          }
          ./hosts/delcatty
        ];
      };
    };
  };
}
