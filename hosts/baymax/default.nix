{
  config,
  inputs,
  pkgs,
  agenix,
  ...
}: let
  user = "me";
  keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOk8iAnIaa1deoc7jw8YACPNVka1ZFJxhnU4G74TmS+p" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC"];
  readeckConfig = (pkgs.formats.toml {}).generate "readeck.toml" config.services.readeck.settings;
  readeckExport = "/mnt/data/backups/readeck-export.zip";
  userGroup = config.users.users.${user}.group;
  userUid = config.users.users.${user}.uid;
  userGid = config.users.groups.${userGroup}.gid;
  cwaConfigDir = "/mnt/data/cwa/config";
  cwaLibraryDir = "/mnt/data/cwa/library";
  cwaIngestDir = "/mnt/data/cwa/ingest";
in {
  imports = [
    ./secrets.nix
    ./disk-config.nix
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
    ];
    kernelPackages = pkgs.linuxPackages_latest;
    kernelModules = ["uinput"];
    # Seagate 0bc2:2344: force usb-storage for SMART; Seagate UAS enclosures block ATA pass-through.
    # https://www.mcgarrah.org/usb-drive-smart/
    kernelParams = ["usb-storage.quirks=0bc2:2344:u"];
  };

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  networking = {
    hostName = "baymax";
    useDHCP = true;
    firewall = {
      enable = true;
      allowedUDPPorts = [config.services.tailscale.port];
      interfaces.tailscale0.allowedTCPPorts = [22 2283 8000 8080 8081];
      interfaces.enp1s0.allowedTCPPorts = [22 2283 8000];
    };
  };

  nix = {
    nixPath = ["nixos-config=/home/${user}/.local/share/src/nixos-config:/etc/nixos"];
    settings = {
      allowed-users = ["${user}"];
      trusted-users = ["@admin" "${user}"];
      substituters = ["https://nix-community.cachix.org" "https://cache.nixos.org"];
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

  # Manages keys and such
  programs = {
    gnupg.agent.enable = true;
    nix-ld.enable = true;
    ssh.extraConfig = ''
      Host *
        SendEnv LANG LC_*
        HashKnownHosts yes

      Host github.com
        IdentitiesOnly yes
        IdentityFile /home/${user}/.ssh/id_github
    '';
    # My shell
    zsh.enable = true;
  };

  services = {
    borgbackup.jobs."local" = {
      paths = [
        "/mnt/data"
        "/home"
      ];
      readWritePaths = [
        "/mnt/data/backups"
      ];
      repo = "/mnt/backup/borg-local";
      removableDevice = true;
      doInit = false;
      persistentTimer = true;
      startAt = "daily";
      compression = "zstd";
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.baymax-borg-pass.path}";
      };
      prune.keep = {
        daily = 7;
        weekly = 4;
        monthly = 6;
      };
    };

    borgbackup.jobs."hetzner" = {
      paths = [
        "/mnt/data"
        "/home"
      ];
      readWritePaths = [
        "/mnt/data/backups"
      ];
      repo = "ssh://u541275@u541275.your-storagebox.de:23/./borg-repo";
      # Triggered via borgbackup-job-local OnSuccess; no independent timer.
      startAt = [];
      compression = "zstd";
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.hetzner-borg-pass.path}";
      };
      environment = {
        BORG_RSH = "ssh -i ${config.age.secrets.hetzner-borg-key.path} -p 23 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${config.age.secrets.hetzner-borg-hosts.path}";
        BORG_REMOTE_PATH = "borg-1.4";
      };
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
      openFirewall = false;
      machine-learning.enable = true;
    };

    # Notification service
    ntfy-sh = {
      enable = true;
      settings = {
        base-url = "http://baymax:8080";
        listen-http = ":8080";
      };
    };

    # Let's be able to SSH into this machine
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [user];
      };
    };

    readeck = {
      enable = true;
      environmentFile = config.age.secrets.readeck-env.path;
      settings = {
        main.log_level = "info";
        server.host = "0.0.0.0";
        server.port = 8000;
      };
    };

    miniflux = {
      enable = true;
      createDatabaseLocally = true;
      adminCredentialsFile = config.age.secrets.miniflux-admin.path;
      config = {
        LISTEN_ADDR = "0.0.0.0:8081";
        BASE_URL = "http://baymax:8081";
      };
    };

    smartd = {
      enable = true;
      autodetect = false;
      extraOptions = ["--interval=1800"];
      defaults.monitored = "-a -o on -S on -s (S/../.././03|L/../../7/04)";
      devices = [
        {
          device = "/dev/disk/by-id/usb-ADATA_HV611_457293242024-0:0";
          options = "-d sat -d removable";
        }
        {
          device = "/dev/disk/by-id/usb-Seagate_Portable_NT3F4401-0:0";
          options = "-d sat -d removable";
        }
      ];
      notifications = {
        mail.enable = false;
        wall.enable = false;
      };
    };

    tailscale = {
      enable = true;
    };

    # Auto mount devices
    udisks2.enable = true;
  };

  # Notification and monitoring systemd units
  systemd = {
    services = {
      # Export Readeck once before the local Borg job, then local success chains hetzner.
      "readeck-export" = {
        description = "Export Readeck payload for Borg jobs";
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = config.age.secrets.readeck-env.path;
          WorkingDirectory = "/var/lib/readeck";
        };
        script = ''
          set -eu
          ${pkgs.coreutils}/bin/rm -f ${readeckExport}
          ${config.services.readeck.package}/bin/readeck export -config ${readeckConfig} ${readeckExport}
        '';
      };

      "borg-check-local-repo-meta" = {
        description = "Run repository-only Borg integrity check for local repo";
        serviceConfig.Type = "oneshot";
        script = ''
          set -eu
          export BORG_REPO=/mnt/backup/borg-local
          export BORG_PASSCOMMAND="cat ${config.age.secrets.baymax-borg-pass.path}"
          ${config.services.borgbackup.package}/bin/borg check --repository-only
        '';
      };

      "borg-check-local-repo-data" = {
        description = "Run full-data Borg integrity check for local repo";
        serviceConfig.Type = "oneshot";
        script = ''
          set -eu
          export BORG_REPO=/mnt/backup/borg-local
          export BORG_PASSCOMMAND="cat ${config.age.secrets.baymax-borg-pass.path}"
          ${config.services.borgbackup.package}/bin/borg check --verify-data
        '';
      };

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
            http://localhost:8080/system "$1 failed on baymax"
        '';
      };

      # Attach failure notifications to critical services
      "readeck-export".unitConfig.OnFailure = "ntfy-failure@%n";
      "borg-check-local-repo-meta".unitConfig.OnFailure = "ntfy-failure@%n";
      "borg-check-local-repo-data".unitConfig.OnFailure = "ntfy-failure@%n";
      "borgbackup-job-local".requires = ["readeck-export.service"];
      "borgbackup-job-local".after = ["readeck-export.service"];
      "borgbackup-job-local".onSuccess = ["borgbackup-job-hetzner.service"];
      "borgbackup-job-local".unitConfig.OnFailure = "ntfy-failure@%n";
      "borgbackup-job-hetzner".unitConfig.OnFailure = "ntfy-failure@%n";
      "immich-server".unitConfig.OnFailure = "ntfy-failure@%n";
      "immich-machine-learning".unitConfig.OnFailure = "ntfy-failure@%n";
      "smartd".unitConfig.OnFailure = "ntfy-failure@%n";

      # Disk space monitoring
      "disk-space-check" = {
        description = "Check mounted disks' space";
        serviceConfig.Type = "oneshot";
        script = ''
          set -eu

          for path in /mnt/data /mnt/backup; do
            usage=$(${pkgs.coreutils}/bin/df "$path" --output=pcent | ${pkgs.coreutils}/bin/tail -1 | ${pkgs.coreutils}/bin/tr -d ' %')
            if [ "$usage" -gt 85 ]; then
              ${pkgs.ntfy-sh}/bin/ntfy publish \
                --title "Disk Space Warning" \
                --priority high \
                --tags warning \
                http://localhost:8080/system "$path is at ''${usage}% capacity"
            fi
          done
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

    timers."borg-check-local-repo-meta" = {
      description = "Weekly Borg metadata check for local repo";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };

    timers."borg-check-local-repo-data" = {
      description = "Monthly Borg full-data check for local repo";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "monthly";
        Persistent = true;
      };
    };

    tmpfiles.rules = [
      "d ${cwaConfigDir} 0755 ${user} ${userGroup} - -"
      "d ${cwaIngestDir} 0755 ${user} ${userGroup} - -"
      "d ${cwaLibraryDir} 0755 ${user} ${userGroup} - -"
    ];
  };

  # Run CWA via Podman (no Docker daemon).
  virtualisation.podman.enable = true;
  virtualisation.oci-containers = {
    backend = "podman";
    containers = {
      calibre-web-automated = {
        # Temporarily disabled.
        autoStart = false;
        image = "crocodilestick/calibre-web-automated:v4.0.4";
        ports = ["0.0.0.0:8083:8083"];
        volumes = [
          "${cwaConfigDir}:/config"
          "${cwaIngestDir}:/cwa-book-ingest"
          "${cwaLibraryDir}:/calibre-library"
        ];
        environment = {
          PUID = toString userUid;
          PGID = toString userGid;
          TZ = config.time.timeZone;
        };
      };
    };
  };

  # It's me, it's you, it's everyone
  users.users = {
    ${user} = {
      isNormalUser = true;
      extraGroups = [
        "wheel" # Enable ‘sudo’ for the user.
      ];
      shell = pkgs.wrapperPackages.zsh;
      openssh.authorizedKeys.keys = keys;
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

  environment.systemPackages = with pkgs;
    [
      agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
    ]
    ++ (import ./packages.nix {inherit pkgs;});

  fileSystems."/mnt/data" = {
    device = "/dev/disk/by-uuid/e39bd467-65ea-4b73-b985-60abe07a4047";
    fsType = "ext4";
    options = ["nofail"];
  };

  fileSystems."/mnt/backup" = {
    device = "/dev/disk/by-uuid/22b41279-319f-4a61-903f-6532f7c2525c";
    fsType = "ext4";
    options = ["nofail"];
  };

  system.stateVersion = "25.11"; # Don't change this
}
