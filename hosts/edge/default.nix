{
  agenix,
  config,
  pkgs,
  ...
}: let
  miniKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC";
  moblinKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBO/2RV9P8Z2/CMbghca654D4sbQ5zbUc7tOJ+x2tcUWILJV3bXeAPI3O+Y65yDU7CojTYje22WBOAWqysmv4LTs= me@moblin";
  bokoblinKey = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBOVxY8n90Qfv17EMNo3T5akdcj6bJZTgqNuMI8k3PxmVe3QIHqEVMDKZUsx2HXNCBiUr3D2XJqaucdObghKa6kY= me@bokoblin";
  publicInterface = "eth0";
in {
  imports = [
    ./secrets.nix
    ./hardware-configuration.nix
    ../../modules/shared
    agenix.nixosModules.default
  ];

  time.timeZone = "UTC";

  networking = {
    hostName = "edge";
    useDHCP = false;
    useNetworkd = true;
    dhcpcd.enable = false;
    nameservers = ["8.8.8.8"];
    nftables.enable = true;
    firewall = {
      enable = true;
      trustedInterfaces = [config.services.tailscale.interfaceName];
      allowedTCPPorts = [22];
      allowedUDPPorts = [config.services.tailscale.port];
      allowedUDPPortRanges = [
        {
          from = 60020;
          to = 60039;
        }
      ];
    };
  };

  nix = {
    settings = {
      allowed-users = ["me"];
      trusted-users = [
        "@admin"
        "me"
      ];
      substituters = [
        "https://nix-community.cachix.org"
        "https://cache.nixos.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
    package = pkgs.nix;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  programs.mosh = {
    enable = true;
    openFirewall = false;
  };

  services = {
    fail2ban.enable = true;
    qemuGuest.enable = true;

    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        AllowUsers = [
          "me"
          "jump"
        ];
      };
      extraConfig = ''
        Match User jump
          AuthenticationMethods publickey
          AllowAgentForwarding no
          AllowTcpForwarding no
          GatewayPorts no
          PermitTunnel no
          X11Forwarding no
      '';
    };

    tailscale = {
      enable = true;
      authKeyFile = config.age.secrets.edge-tailscale-key.path;
      extraUpFlags = [
        "--accept-dns=true"
      ];
    };
  };

  systemd = {
    network.wait-online.enable = false;
    network.enable = true;
    network.links."10-public" = {
      matchConfig.PermanentMACAddress = "92:00:07:51:a8:e2";
      linkConfig.Name = publicInterface;
    };
    network.networks."10-public" = {
      matchConfig.Name = publicInterface;
      DHCP = "no";
      address = [
        "89.167.121.58/32"
        "2a01:4f9:c014:3c5e::1/64"
        "fe80::9000:7ff:fe51:a8e2/64"
      ];
      routes = [
        {
          Destination = "172.31.1.1/32";
        }
        {
          Gateway = "172.31.1.1";
        }
        {
          Destination = "fe80::1/128";
        }
        {
          Gateway = "fe80::1";
        }
      ];
      networkConfig.IPv6PrivacyExtensions = "kernel";
    };
    services.tailscaled.serviceConfig.Environment = [
      "TS_DEBUG_FIREWALL_MODE=nftables"
    ];
  };

  boot.initrd.systemd.network.wait-online.enable = false;

  environment.systemPackages =
    [
      agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
    ]
    ++ (with pkgs; [
      curl
      jq
      lnav
      mosh
      ncdu
      ripgrep
      tree
      vim
    ]);

  users = {
    users = {
      me = {
        isNormalUser = true;
        extraGroups = ["wheel"];
        openssh.authorizedKeys.keys = [miniKey];
        shell = pkgs.wrapperPackages.zsh;
        hashedPasswordFile = config.age.secrets.edge-pass.path;
      };

      jump = {
        isNormalUser = true;
        openssh.authorizedKeys.keys = [miniKey moblinKey bokoblinKey];
      };
    };

    mutableUsers = false;
  };

  security = {
    apparmor.enable = true;
    sudo = {
      execWheelOnly = true;
      extraConfig = ''
        Defaults lecture = never
      '';
    };
  };

  system.stateVersion = "25.11";
}
