{
  imports = [
    ../../modules/nixos/wsl-dev.nix
  ];

  networking.hostName = "delcatty";
  system.stateVersion = "25.11";

  local.wslDev = {
    enable = true;
    user = "nixos";
    flakePath = "/home/nixos/nix-config";
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvCa1xa2EJLNl4lTFtBSPDWpi0uiuE34kpCxkfDYz8r mini-darwin nix builder for baymax"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIaUXyO37/x5lwDapVXjT3PGJwbxyrW3dZEH6/uh6i/k me@lizalfos"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVxY8n90Qfv17EMNo3T5akdcj6bJZTgqNuMI8k3PxmVe3QIHqEVMDKZUsx2HXNCBiUr3D2XJqaucdObghKa6kY= me@bokoblin"
    ];
  };
}
