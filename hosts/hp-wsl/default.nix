{
  imports = [
    ../../modules/nixos/wsl-dev.nix
  ];

  networking.hostName = "hp-wsl";
  system.stateVersion = "26.05";

  local.wslDev = {
    enable = true;
    user = "me";
    enableSshServer = true;
    authorizedKeys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvCa1xa2EJLNl4lTFtBSPDWpi0uiuE34kpCxkfDYz8r mini-darwin nix builder for baymax"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBO/2RV9P8Z2/CMbghca654D4sbQ5zbUc7tOJ+x2tcUWILJV3bXeAPI3O+Y65yDU7CojTYje22WBOAWqysmv4LTs= me@moblin"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIaUXyO37/x5lwDapVXjT3PGJwbxyrW3dZEH6/uh6i/k me@lizalfos"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVxY8n90Qfv17EMNo3T5akdcj6bJZTgqNuMI8k3PxmVe3QIHqEVMDKZUsx2HXNCBiUr3D2XJqaucdObghKa6kY= me@bokoblin"
    ];
  };
}
