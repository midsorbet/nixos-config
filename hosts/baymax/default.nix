{
  config,
  pkgs,
  lib,
  agenix,
  ...
}: let
  user = "me";
  keys = {
    boot = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC"
    ];
    login = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC"
    ];
  };
in {
  imports = [
    ./secrets.nix
    ./disk-config.nix
    ../../modules/shared
    agenix.nixosModules.default
  ];

  boot = {
    loader = {
      systemd-boot.enable = lib.mkForce false;
      efi.canTouchEfiVariables = true;
    };
    lanzaboote = {
      enable = true;
      # Persist Secure Boot PKI material across rebuilds/reboots.
      pkiBundle = "/persist/sbctl";
      # Do not allow unsigned UKIs once keys exist.
      allowUnsigned = false;
      autoGenerateKeys.enable = true;
      autoEnrollKeys.enable = true;
    };
    initrd.availableKernelModules = [
      "xhci_pci"
      "ahci"
      "nvme"
      "usbhid"
      "usb_storage"
      "sd_mod"
      "igc"
    ];
    initrd.network = {
      enable = true;
      ssh = {
        enable = true;
        port = 2222;
        authorizedKeys = keys.boot;
        hostKeys = ["/persist/secrets/initrd/ssh_host_ed25519_key"];
      };
      postCommands = ''
        zpool import -N -d /dev/disk/by-id rpool
        echo 'zfs load-key -L prompt rpool && killall zfs; exit' > /root/.profile
      '';
    };
    initrd.postDeviceCommands = lib.mkAfter ''
      zfs rollback -r rpool/root@blank && echo " >> >> Rollback Complete << <<"
    '';
    supportedFilesystems = ["zfs"];
    kernelPackages = pkgs.linuxPackages_6_12;
    kernelModules = ["uinput"];
    # Force usb-storage (disable UAS) for the Seagate enclosure to avoid reset/timeouts.
    kernelParams = ["usb-storage.quirks=0bc2:2344:u"];
  };

  fileSystems."/persist".neededForBoot = true;
  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/lib/tailscale"
      "/var/log/journal"
    ];
  };
  environment.etc."machine-id".source = "/persist/etc/machine-id";

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  networking = {
    hostName = "baymax";
    hostId = "378a1cd8";
    useDHCP = true;
    firewall = {
      enable = true;
      allowedUDPPorts = [config.services.tailscale.port];
      interfaces.tailscale0.allowedTCPPorts = [22 2283 8000 8080 8081 28981];
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
    fail2ban = {
      enable = true;
      maxretry = 5;
      bantime = "1h";
      jails = {
        # Watches paperless-web journald logs for repeated failed logins.
        paperless-auth = {
          filter.Definition = {
            failregex = "Login failed for user `.*` from (?:IP|private IP) `<HOST>`\\.$";
            ignoreregex = "";
          };
          settings = {
            backend = "systemd";
            journalmatch = "_SYSTEMD_UNIT=paperless-web.service";
            port = "28981";
            maxretry = 5;
            findtime = "10m";
            bantime = "1h";
          };
        };
      };
    };

    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };

    borgbackup.jobs."hetzner" = {
      paths = [
        "/mnt/data"
        "/home"
        "/persist/secrets"
        "/persist/sbctl"
        "/persist/etc/machine-id"
      ];
      repo = "ssh://u541275@u541275.your-storagebox.de:23/./borg-repo";
      startAt = "daily";
      persistentTimer = true;
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

    postgresqlBackup = {
      enable = true;
      backupAll = true;
      compression = "zstd";
      compressionLevel = 6;
      location = "/mnt/data/postgresql/dumps";
      startAt = [];
    };

    immich = {
      enable = true;
      host = "0.0.0.0";
      port = 2283;
      mediaLocation = "/mnt/data/immich";
      openFirewall = false;
      machine-learning.enable = true;
    };

    ntfy-sh = {
      enable = true;
      settings = {
        base-url = "http://baymax:8080";
        listen-http = ":8080";
        auth-default-access = "deny-all";
        auth-access = ["*:system:read-write"];
      };
    };

    openssh = {
      enable = true;
      hostKeys = [
        {
          path = "/persist/secrets/ssh/ssh_host_ed25519_key";
          type = "ed25519";
        }
      ];
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
        main.data_directory = "/mnt/data/readeck";
        main.log_level = "info";
        server.host = "0.0.0.0";
        server.port = 8000;
      };
    };

    postgresql.dataDir = "/mnt/data/postgresql/${config.services.postgresql.package.psqlSchema}";

    miniflux = {
      enable = true;
      createDatabaseLocally = true;
      adminCredentialsFile = config.age.secrets.miniflux-admin.path;
      config = {
        LISTEN_ADDR = "0.0.0.0:8081";
        BASE_URL = "http://baymax:8081";
      };
    };

    paperless = {
      enable = true;
      address = "0.0.0.0";
      dataDir = "/mnt/data/paperless";
      passwordFile = config.age.secrets.paperless.path;
      configureTika = true;
      settings = {
        PAPERLESS_URL = "http://baymax:28981";
        PAPERLESS_CONSUMER_RECURSIVE = true;
        PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;
      };
      exporter = {
        enable = true;
        onCalendar = "Sun *-*-* 23:30:00";
      };
    };

    smartd = {
      enable = true;
      autodetect = false;
      extraOptions = ["--interval=1800"];
      defaults.monitored = "-a -o on -S on -s (S/../.././03|L/../../7/04)";
      devices = [
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
  };

  # Notification and monitoring systemd units
  systemd = {
    services = {
      readeck.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = lib.mkForce "readeck";
        Group = lib.mkForce "readeck";
        NoNewPrivileges = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        LockPersonality = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectControlGroups = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectHome = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
        CapabilityBoundingSet = [""];
        AmbientCapabilities = [""];
        ReadWritePaths = [config.services.readeck.settings.main.data_directory];
      };

      "immich-server".serviceConfig = {
        SystemCallArchitectures = "native";
        LockPersonality = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        RemoveIPC = true;
      };

      "ntfy-sh".serviceConfig = {
        SystemCallArchitectures = "native";
        LockPersonality = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectHome = true;
        ProtectProc = "invisible";
        ProcSubset = "pid";
        PrivateUsers = true;
        RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
        UMask = "0077";
        RemoveIPC = true;
      };

      "readeck-export" = {
        description = "Export Readeck payload for Borg jobs";
        serviceConfig = {
          Type = "oneshot";
          EnvironmentFile = config.age.secrets.readeck-env.path;
          WorkingDirectory = config.services.readeck.settings.main.data_directory;
          ExecStartPre = [
            "${pkgs.coreutils}/bin/rm -f ${config.services.readeck.settings.main.data_directory}/readeck-export.zip"
          ];
        };
        script = ''
          set -eu
          ${config.services.readeck.package}/bin/readeck export -config ${(pkgs.formats.toml {}).generate "readeck.toml" config.services.readeck.settings} ${config.services.readeck.settings.main.data_directory}/readeck-export.zip
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
      "postgresqlBackup".unitConfig.OnFailure = "ntfy-failure@%n";
      "paperless-exporter".unitConfig.OnFailure = "ntfy-failure@%n";
      "borgbackup-job-hetzner".requires = [
        "readeck-export.service"
        "postgresqlBackup.service"
      ];
      "borgbackup-job-hetzner".after = [
        "readeck-export.service"
        "postgresqlBackup.service"
      ];
      "borgbackup-job-hetzner".unitConfig.OnFailure = "ntfy-failure@%n";
      "immich-server".unitConfig.OnFailure = "ntfy-failure@%n";
      "immich-machine-learning".unitConfig.OnFailure = "ntfy-failure@%n";
      "smartd".unitConfig.OnFailure = "ntfy-failure@%n";

      # Disk space monitoring
      "disk-space-check" = {
        description = "Check ZFS pool capacity";
        serviceConfig.Type = "oneshot";
        script = ''
          set -eu

          alerts="$(
            ${pkgs.zfs}/bin/zpool list -H -o name,capacity \
              | ${pkgs.gawk}/bin/awk -F '\t' '$2 + 0 >= 75 { printf "%s is at %s capacity\n", $1, $2 }'
          )"

          if [ -n "$alerts" ]; then
            ${pkgs.ntfy-sh}/bin/ntfy publish \
              --title "ZFS Pool Warning" \
              --priority high \
              --tags warning \
              http://localhost:8080/system "$alerts"
          fi
        '';
      };
    };

    timers."disk-space-check" = {
      description = "Daily disk space check";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnCalendar = "*-*-* 00:20:00";
        Persistent = true;
      };
    };

    tmpfiles.settings."20-baymax-data-paths" = {
      "${config.services.immich.mediaLocation}".d = {
        user = config.services.immich.user;
        group = config.services.immich.group;
        mode = "0700";
      };
      "${config.services.readeck.settings.main.data_directory}".d = {
        user = "readeck";
        group = "readeck";
        mode = "0700";
      };
      "${config.services.postgresql.dataDir}".d = {
        user = "postgres";
        group = "postgres";
        mode = "0700";
      };
      "${config.services.postgresqlBackup.location}".d = {
        user = "postgres";
        group = "postgres";
        mode = "0700";
      };
    };
  };

  # It's me, it's you, it's everyone
  users = {
    users = {
      ${user} = {
        isNormalUser = true;
        extraGroups = [
          "wheel" # Enable ‘sudo’ for the user.
        ];
        hashedPasswordFile = "/persist/secrets/users/me-password-hash";
        shell = pkgs.wrapperPackages.zsh;
        openssh.authorizedKeys.keys = keys.login;
      };

      readeck = {
        isSystemUser = true;
        group = "readeck";
      };
    };

    groups.readeck = {};

    mutableUsers = false;
  };

  security = {
    audit = {
      enable = true;
      backlogLimit = 8192;
    };
    apparmor.enable = true;

    # Don't require password for users in `wheel` group for these commands
    sudo = {
      enable = true;
      extraConfig = ''
        Defaults lecture = never
      '';
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
  };

  environment.systemPackages = with pkgs;
    [
      agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
    ]
    ++ (import ./packages.nix {inherit pkgs;});

  system.stateVersion = "25.11"; # Don't change this
}
