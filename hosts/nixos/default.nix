{
  config,
  inputs,
  pkgs,
  agenix,
  ...
}: let
  user = "me";
  keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk8iAnIaa1deoc7jw8YACPNVka1ZFJxhnU4G74TmS+p" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC"];
in {
  imports = [
    ../../modules/nixos/secrets.nix
    ../../modules/nixos/disk-config.nix
    ../../modules/shared
    agenix.nixosModules.default
  ];

  # Use the systemd-boot EFI boot loader.
  boot = {
    loader = {
      systemd-boot = {
        enable = true;
        configurationLimit = 42;
      };
      efi.canTouchEfiVariables = true;
    };
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usbhid"
      "usb_storage"
      "sd_mod"
      # VirtIO modules for better VM performance
      "virtio_pci"
      "virtio_blk"
      "virtio_scsi"
      "virtio_net"
    ];
    kernelPackages = pkgs.linuxPackages_latest;
    kernelModules = ["uinput" "virtio_balloon" "virtio_console" "virtio_rng"];
  };

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  networking = {
    hostName = "mini-nix";
    useDHCP = true;
    firewall = {
      enable = true;
      trustedInterfaces = ["tailscale0"];
      allowedUDPPorts = [config.services.tailscale.port];
      allowedTCPPorts = [22];
    };
  };

  nix = {
    nixPath = ["nixos-config=/home/${user}/.local/share/src/nixos-config:/etc/nixos"];
    settings = {
      allowed-users = ["${user}"];
      trusted-users = ["@admin" "${user}"];
      substituters = ["https://nix-community.cachix.org" "https://cache.nixos.org"];
      trusted-public-keys = ["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="];
    };

    package = pkgs.nix;
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Manages keys and such
  programs = {
    gnupg.agent.enable = true;
    nix-ld.enable = true;
    # My shell
    zsh.enable = true;
  };

  services = {
    borgbackup.jobs."immich" = {
      paths = "/mnt/data/immich";
      repo = "/mnt/data/backups/borg-immich";
      startAt = "daily";
      compression = "zstd";
      encryption.mode = "none";
      prune.keep = {
        daily = 7;
        weekly = 4;
        monthly = 6;
      };
    };
    immich = {
      enable = true;
      host = "0.0.0.0";
      port = 2283;
      mediaLocation = "/mnt/data/immich";
      openFirewall = true;
      machine-learning.enable = true;
    };

    # Let's be able to SSH into this machine
    openssh.enable = true;

    # QEMU guest agent for better host integration (graceful shutdown, etc.)
    qemuGuest.enable = true;

    # Sync state between machines
    syncthing = {
      enable = true;
      openDefaultPorts = true;
      dataDir = "/home/${user}/.local/share/syncthing";
      configDir = "/home/${user}/.config/syncthing";
      user = "${user}";
      group = "users";
      guiAddress = "127.0.0.1:8384";
      overrideFolders = true;
      overrideDevices = true;

      settings = {
        devices = {};
        options.globalAnnounceEnabled = false; # Only sync on LAN
      };
    };

    tailscale = {
      enable = true;
    };

    # Notification service (accessible via Tailscale)
    ntfy-sh = {
      enable = true;
      settings = {
        base-url = "http://mini-nix:8080";
        listen-http = ":8080";
      };
    };
  };

  # Notification and monitoring systemd units
  systemd = {
    services = {
      # Template service for failure notifications
      "ntfy-failure@" = {
        description = "Send failure notification for %i";
        serviceConfig.Type = "oneshot";
        scriptArgs = "%i";
        script = ''
          ${pkgs.ntfy-sh}/bin/ntfy publish \
            --title "Service Failed" \
            --priority high \
            --tags warning \
            http://localhost:8080/system "$1 failed on mini-nix"
        '';
      };

      # Attach failure notifications to critical services
      "borgbackup-job-immich".unitConfig.OnFailure = "ntfy-failure@%n";
      "immich-server".unitConfig.OnFailure = "ntfy-failure@%n";
      "immich-machine-learning".unitConfig.OnFailure = "ntfy-failure@%n";

      # Disk space monitoring
      "disk-space-check" = {
        description = "Check disk space on /mnt/data";
        serviceConfig.Type = "oneshot";
        script = ''
          usage=$(${pkgs.coreutils}/bin/df /mnt/data --output=pcent | ${pkgs.coreutils}/bin/tail -1 | ${pkgs.coreutils}/bin/tr -d ' %')
          if [ "$usage" -gt 85 ]; then
            ${pkgs.ntfy-sh}/bin/ntfy publish \
              --title "Disk Space Warning" \
              --priority high \
              --tags warning \
              http://localhost:8080/system "/mnt/data is at ''${usage}% capacity"
          fi
        '';
      };
    };

    timers."disk-space-check" = {
      description = "Daily disk space check";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
      };
    };
  };

  # Add docker daemon
  virtualisation.docker.enable = true;
  virtualisation.docker.logDriver = "json-file";

  # It's me, it's you, it's everyone
  users.users = {
    ${user} = {
      isNormalUser = true;
      extraGroups = [
        "wheel" # Enable ‘sudo’ for the user.
        "docker"
      ];
      shell = pkgs.zsh;
      openssh.authorizedKeys.keys = keys;
    };

    backup = {
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        ''command="${pkgs.rrsync}/bin/rrsync -ro /mnt/data/backups",restrict ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC me@mini-me.local''
      ];
    };

    root = {
      openssh.authorizedKeys.keys = keys;
    };
  };

  # Don't require password for users in `wheel` group for these commands
  security.sudo = {
    enable = true;
    extraRules = [
      {
        commands = [
          {
            command = "${pkgs.systemd}/bin/reboot";
            options = ["NOPASSWD"];
          }
        ];
        groups = ["wheel"];
      }
    ];
  };

  environment.systemPackages = with pkgs; [
    agenix.packages."${pkgs.system}".default
    gitFull
    inetutils
  ];

  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/e39bd467-65ea-4b73-b985-60abe07a4047";
    fsType = "ext4";
    options = ["nofail"];
  };

  system.stateVersion = "25.11"; # Don't change this
}
