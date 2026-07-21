{
  config,
  pkgs,
  lib,
  agenix,
  ...
}: let
  domain = "midsorbet.me";
  user = "me";
  ompBrokerPort = 8765;
  keys = {
    boot = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC"
    ];
    login = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvCa1xa2EJLNl4lTFtBSPDWpi0uiuE34kpCxkfDYz8r mini-darwin nix builder for baymax"
      "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBO/2RV9P8Z2/CMbghca654D4sbQ5zbUc7tOJ+x2tcUWILJV3bXeAPI3O+Y65yDU7CojTYje22WBOAWqysmv4LTs= me@moblin"
    ];
  };
in {
  # The pinned nixpkgs cloudflared module only supports credentials-file
  # tunnels. Baymax uses a Cloudflare-managed tunnel token from agenix, so keep
  # the local module until upstream supports tokenFile or the secret is migrated
  # to a credentials JSON file.
  disabledModules = ["services/networking/cloudflared.nix"];

  imports = [
    ./secrets.nix
    ./disk-config.nix
    ./cloudflared-module.nix
    ../../modules/shared
    agenix.nixosModules.default
  ];

  local.git = {
    enable = true;
    inherit user;
  };
  local.zsh = {
    enable = true;
    inherit user;
  };

  boot = {
    loader = {
      efi.canTouchEfiVariables = true;
      systemd-boot.configurationLimit = 20;
    };
    lanzaboote = {
      enable = true;
      # Persist Secure Boot PKI material across rebuilds/reboots.
      pkiBundle = "/persist/host/sbctl";
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
        hostKeys = ["/persist/host/secrets/initrd/ssh_host_ed25519_key"];
      };
    };
    initrd.systemd = {
      initrdBin = [
        (pkgs.writeShellScriptBin "initrd-ask-password" ''
          exec ${config.boot.initrd.systemd.package}/bin/systemd-tty-ask-password-agent --watch
        '')
      ];
      users.root.shell = "/bin/initrd-ask-password";
      services.zfs-rollback-root = {
        description = "Rollback ephemeral root dataset";
        requiredBy = ["sysroot.mount"];
        after = ["zfs-import-rpool.service"];
        before = ["sysroot.mount"];
        unitConfig.DefaultDependencies = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          ${config.boot.zfs.package}/sbin/zfs rollback -r rpool/root@blank
          echo " >> >> Rollback Complete << <<"
        '';
      };
    };
    supportedFilesystems = ["zfs"];
    kernelModules = [
      "uinput"
      "tun"
    ];
    # Force usb-storage (disable UAS) for the Seagate enclosure to avoid reset/timeouts.
    kernelParams = ["usb-storage.quirks=0bc2:2344:u"];
    zfs.forceImportRoot = false;
  };

  fileSystems = {
    "/persist".neededForBoot = true;
    "/persist/host".neededForBoot = true;
  };

  environment.persistence."/persist" = {
    hideMounts = true;

    directories = [
      "/var/lib/nixos"
      "/var/lib/systemd"
      "/var/lib/cloudflare-warp"
      "/var/log/journal"
    ];
  };

  # Use impermanence's machine-id handling instead of a manual /etc symlink so
  # systemd and D-Bus always see a normal readable file early in boot.
  environment.persistence."/persist/host" = {
    hideMounts = true;
    files = ["/etc/machine-id"];
  };

  # Set your time zone.
  time.timeZone = "America/Los_Angeles";

  networking = {
    hostName = "baymax";
    hostId = "378a1cd8";
    useDHCP = true;
    # dhcpcd failed during the Baymax recovery boot; keep systemd-networkd as
    # the DHCP backend for this host.
    useNetworkd = true;
    firewall = {
      enable = true;
      interfaces.CloudflareWARP.allowedTCPPorts = [22 2283];
      interfaces.enp1s0.allowedTCPPorts = [22 2283 ompBrokerPort];
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
    ssh = {
      knownHosts.github = {
        hostNames = ["github.com"];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
      };
      extraConfig = ''
        Host *
          SendEnv LANG LC_*
          HashKnownHosts yes

        Host github.com
          IdentitiesOnly yes
          IdentityFile /home/${user}/.ssh/id_github
      '';
    };
    # My shell
    zsh.enable = true;
  };

  services = {
    zfs = {
      autoScrub.enable = true;
      trim.enable = true;
    };

    sanoid = {
      enable = true;
      datasets = {
        "rpool/persistHost" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 30;
          weekly = 12;
          monthly = 12;
        };
        "data/persistSave" = {
          autosnap = true;
          autoprune = true;
          hourly = 24;
          daily = 14;
          weekly = 8;
          monthly = 6;
        };
        "archive/media" = {
          autosnap = true;
          autoprune = true;
          hourly = 0;
          daily = 14;
          weekly = 12;
          monthly = 12;
        };
        "archive/replica" = {
          autosnap = false;
          autoprune = true;
          hourly = 0;
          daily = 30;
          weekly = 0;
          monthly = 6;
          yearly = 0;
        };
      };
    };

    syncoid = {
      enable = true;
      user = "root";
      group = "root";
      interval = "daily";
      commonArgs = ["--no-sync-snap"];
      commands."baymax-persist-save" = {
        source = "data/persistSave";
        target = "archive/replica/baymax-persistSave";
        recursive = true;
      };
      commands."baymax-persist-host" = {
        source = "rpool/persistHost";
        target = "archive/replica/baymax-persistHost";
        recursive = true;
      };
    };

    borgbackup.jobs."hetzner" = {
      paths = [
        "/persist/save"
        "/persist/host"
        "/home"
        "/archive/immich"
      ];
      repo = "ssh://u583523@u583523.your-storagebox.de:23/./borg-repo";
      extraArgs = ["--remote-path=borg-1.4"];
      startAt = "daily";
      persistentTimer = true;
      compression = "zstd";
      encryption = {
        mode = "repokey-blake2";
        passCommand = "cat ${config.age.secrets.hetzner-borg-pass.path}";
      };
      environment = {
        BORG_RSH = "ssh -i ${config.age.secrets.hetzner-borg-key.path} -p 23 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${config.age.secrets.hetzner-borg-hosts.path}";
      };
      prune.keep = {
        daily = 7;
        weekly = 8;
        monthly = 12;
      };
    };

    postgresqlBackup = {
      enable = true;
      backupAll = true;
      compression = "zstd";
      compressionLevel = 6;
      location = "/persist/save/postgresql/dumps";
      startAt = [];
    };

    immich = {
      enable = true;
      host = "0.0.0.0";
      port = 2283;
      mediaLocation = "/archive/immich";
      environment = {
        THUMB_LOCATION = "/persist/cache/immich/thumbs";
        ENCODED_VIDEO_LOCATION = "/persist/cache/immich/encoded-video";
        PROFILE_LOCATION = "/persist/save/immich/profile";
        BACKUP_LOCATION = "/persist/save/immich/backups";
      };
      openFirewall = false;
      machine-learning.enable = true;
    };

    ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://ntfy.${domain}";
        listen-http = "127.0.0.1:8080";
        auth-default-access = "deny-all";
        auth-access = ["*:system:read-write"];
      };
    };

    openssh = {
      enable = true;
      hostKeys = [
        {
          path = "/persist/host/secrets/ssh/ssh_host_ed25519_key";
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
        main.data_directory = "/persist/save/readeck";
        main.log_level = "info";
        server.base_url = "https://readeck.${domain}";
        server.allowed_hosts = ["readeck.${domain}"];
        server.host = "127.0.0.1";
        server.port = 8000;
      };
    };

    postgresql.dataDir = "/persist/save/postgresql/${config.services.postgresql.package.psqlSchema}";

    miniflux = {
      enable = true;
      createDatabaseLocally = true;
      adminCredentialsFile = config.age.secrets.miniflux-admin.path;
      config = {
        LISTEN_ADDR = "127.0.0.1:8081";
        BASE_URL = "https://rss.${domain}";
      };
    };

    paperless = {
      enable = true;
      address = "127.0.0.1";
      dataDir = "/persist/save/paperless";
      passwordFile = config.age.secrets.paperless.path;
      configureTika = true;
      settings = {
        PAPERLESS_URL = "https://paperless.${domain}";
        PAPERLESS_CONSUMER_RECURSIVE = true;
        PAPERLESS_CONSUMER_SUBDIRS_AS_TAGS = true;
      };
      exporter = {
        enable = true;
        onCalendar = null;
      };
    };

    smartd = {
      enable = true;
      autodetect = false;
      extraOptions = ["--interval=1800"];
      defaults.monitored = "-a -o on -S on -s (S/../.././03|L/../../7/04)";
      devices = [
        {
          device = "/dev/disk/by-id/ata-512GB_SSD_MQ23W96605594";
          options = "";
        }
        {
          device = "/dev/disk/by-id/nvme-SPCC_M.2_PCIe_SSD_20250501B1514";
          options = "-d nvme";
        }
        {
          device = "/dev/disk/by-id/wwn-0x5000c500eb0059f5";
          options = "-d sat -d removable";
        }
      ];
      notifications = {
        mail.enable = false;
        wall.enable = false;
      };
    };

    "cloudflare-warp" = {
      enable = true;
      # On WARP updates, verify the headless install still succeeds. Nixpkgs
      # 2026.6.822 tries to remove a GUI path missing from its Debian archive.
      package = pkgs.cloudflare-warp.override {headless = true;};
    };

    avahi = {
      enable = true;
      nssmdns4 = true;
      openFirewall = true;
    };

    cloudflared = {
      enable = true;
      tunnels."baymax-apps".tokenFile = config.age.secrets."baymax-tunnel".path;
    };
  };

  # Notification and monitoring systemd units
  systemd = {
    services = {
      # systemd 260 tmpfiles --clean exits 73/CANTCREAT when statx(2) hits
      # Baymax's ZFS-backed /tmp, /var/tmp, /nix, and /var/lib/systemd paths.
      # Keep the cleanup attempt visible in the journal, but do not leave the
      # host degraded for this non-fatal compatibility failure.
      "systemd-tmpfiles-clean".serviceConfig.SuccessExitStatus = "CANTCREAT";

      "omp-auth-broker" = {
        description = "OMP authentication broker";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        environment.HOME = "/home/${user}";
        serviceConfig = {
          Type = "simple";
          ExecStart = "${lib.getExe pkgs.omp} auth-broker serve --bind=0.0.0.0:${toString ompBrokerPort}";
          Restart = "on-failure";
          RestartSec = "5s";
          User = user;
          Group = "users";
          WorkingDirectory = "/home/${user}";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = "read-only";
          ReadWritePaths = ["/home/${user}/.omp"];
          RestrictAddressFamilies = ["AF_UNIX" "AF_INET" "AF_INET6"];
          CapabilityBoundingSet = [""];
          AmbientCapabilities = [""];
          SystemCallArchitectures = "native";
          LockPersonality = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictSUIDSGID = true;
        };
      };

      readeck.serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "readeck";
        Group = "readeck";
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
        wants = ["ntfy-sh.service"];
        after = ["ntfy-sh.service"];
        unitConfig = {
          StartLimitIntervalSec = 300;
          StartLimitBurst = 5;
        };
        serviceConfig = {
          Type = "oneshot";
          Restart = "on-failure";
          RestartSec = "30s";
        };
        scriptArgs = "%i";
        script = ''
          ${pkgs.ntfy-sh}/bin/ntfy publish \
            --title "Service Failed" \
            --priority high \
            --tags warning \
            http://127.0.0.1:8080/system "$1 failed on baymax"
        '';
      };

      # Attach failure notifications to critical services
      "readeck-export".unitConfig.OnFailure = "ntfy-failure@%n";
      "postgresqlBackup" = {
        requires = ["postgresql.service"];
        after = ["postgresql.service"];
        unitConfig.OnFailure = "ntfy-failure@%n";
      };
      "paperless-exporter".unitConfig.OnFailure = "ntfy-failure@%n";
      "borgbackup-job-hetzner".requires = [
        "paperless-exporter.service"
        "readeck-export.service"
        "postgresqlBackup.service"
      ];
      "borgbackup-job-hetzner".after = [
        "paperless-exporter.service"
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

    tmpfiles.settings."20-baymax-data-paths" = let
      mkTmpDirEntries = dirUser: dirGroup: dirMode: dirs:
        lib.genAttrs dirs (_dir: {
          d = {
            user = dirUser;
            group = dirGroup;
            mode = dirMode;
          };
        });
    in
      (mkTmpDirEntries "root" "root" "0751" [
        "/persist/host"
      ])
      // (mkTmpDirEntries "root" "root" "0750" [
        "/persist/cache"
      ])
      // (mkTmpDirEntries "root" "root" "0700" [
        "/persist/host/secrets"
        "/persist/host/secrets/zfs"
        "/persist/host/sbctl"
      ])
      // (mkTmpDirEntries "root" "root" "0755" [
        "/persist/host/etc"
      ])
      // {
        # Compatibility for older Baymax generations whose initrd secret copy
        # hooks used /persist/secrets before host-specific state moved under
        # /persist/host.
        "/persist/secrets".L.argument = "/persist/host/secrets";
        "/persist/host/etc/machine-id".z = {
          user = "root";
          group = "root";
          mode = "0444";
        };
      }
      // (mkTmpDirEntries user "users" "0700" [
        "/home/${user}/.omp"
        "/home/${user}/.omp/agent"
      ])
      // (mkTmpDirEntries config.services.immich.user config.services.immich.group "0700" [
        config.services.immich.mediaLocation
        config.services.immich.environment.THUMB_LOCATION
        config.services.immich.environment.ENCODED_VIDEO_LOCATION
        config.services.immich.environment.PROFILE_LOCATION
        config.services.immich.environment.BACKUP_LOCATION
      ])
      // {
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
        hashedPasswordFile = "/persist/host/secrets/users/me-password-hash";
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
    lockKernelModules = true;
    protectKernelImage = true;

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
            {
              command = "${pkgs.systemd}/bin/systemctl start nixos-upgrade.service";
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

  system = {
    autoUpgrade = {
      enable = true;
      # Follow reviewed commits and their locked inputs. Flake input refreshes
      # should happen through repo commits, not independently on Baymax.
      flake = "git+ssh://git@github.com/midsorbet/nixos-config.git#baymax";
      upgrade = false;
      dates = "Sun 04:40";
      randomizedDelaySec = "2h";
      fixedRandomDelay = true;
      persistent = false;
      allowReboot = true;
      rebootWindow = {
        lower = "04:00";
        upper = "07:00";
      };
    };

    stateVersion = "25.11"; # Don't change this
  };
}
