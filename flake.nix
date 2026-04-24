{
  description = "Starter Configuration with secrets for MacOS and NixOS";
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    agenix.url = "github:ryantm/agenix";
    wrapper-manager.url = "github:viperML/wrapper-manager";
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
    disko = {
      url = "github:nix-community/disko";
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
      url = "github:nix-community/lanzaboote/v1.0.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    secrets = {
      url = "git+ssh://git@github.com/midsorbet/nix-secrets.git";
      flake = false;
    };
    vscode-server.url = "github:nix-community/nixos-vscode-server";
    zmx.url = "github:neurosnap/zmx/v0.5.0";
    mdfried = {
      url = "github:benjajaja/mdfried/v0.19.5";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    darwin,
    nix-homebrew,
    homebrew-bundle,
    homebrew-core,
    homebrew-cask,
    nixpkgs,
    disko,
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
    devShell = system: let
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      default = with pkgs;
        mkShell {
          nativeBuildInputs = with pkgs; [bashInteractive git age nixd uv];
        };
    };
  in {
    devShells = forAllSystems devShell;
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);

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
    };
  };
}
