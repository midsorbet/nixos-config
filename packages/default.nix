{
  inputs,
  system,
  config ? {},
}:
import inputs.nixpkgs {
  inherit system config;
  overlays = [
    (import ./overlay.nix {inherit inputs;})
  ];
}
