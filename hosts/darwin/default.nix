{
  agenix,
  config,
  pkgs,
  ...
}: let
  user = "me";
in {
  imports = [
    ../../modules/darwin/secrets.nix
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
    agenix.darwinModules.default
  ];

  # Setup user, packages, programs
  nix = {
    package = pkgs.nix;

    settings = {
      trusted-users = ["@admin" "${user}"];
      substituters = ["https://nix-community.cachix.org" "https://cache.nixos.org"];
      trusted-public-keys = ["cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="];
    };

    gc = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 2;
        Minute = 0;
      };
      options = "--delete-older-than 30d";
    };

    extraOptions = ''
      experimental-features = nix-command flakes
      extra-platforms = x86_64-darwin aarch64-darwin
    '';

    linux-builder.enable = true;
  };

  # Turn off NIX_PATH warnings now that we're using flakes

  # Load configuration that is shared across systems
  environment.systemPackages = with pkgs;
    [
      agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
    ]
    ++ (import ../../modules/shared/packages.nix {inherit pkgs;});

  networking.knownNetworkServices = [
    "Ethernet"
    "Thunderbolt Bridge"
    "Wi-Fi"
  ];

  services.aerospace = {
    enable = true;
    settings = {
      config-version = 2;
      enable-normalization-flatten-containers = false;
      enable-normalization-opposite-orientation-for-nested-containers = false;
      on-focus-changed = ["move-mouse window-lazy-center"];
      gaps = {
        inner.horizontal = 10;
        inner.vertical = 10;
        outer.left = 5;
        outer.right = 5;
        outer.top = 5;
        outer.bottom = 5;
      };
      workspace-to-monitor-force-assignment = {
        "1" = "main";
        "2" = "main";
        "3" = "main";
        "4" = "main";
        "5" = "main";
        "6" = "main";
        "7" = "main";
        "8" = "main";
        "9" = "main";
        A = "secondary";
        B = "secondary";
        C = "secondary";
        D = "secondary";
        E = "secondary";
        F = "secondary";
      };
      on-window-detected = [
        {
          "if".app-id = "org.mozilla.firefox";
          run = "move-node-to-workspace A";
        }
        {
          "if".app-id = "com.anthropic.claudefordesktop";
          run = "move-node-to-workspace C";
        }
        {
          "if".app-id = "com.mitchellh.ghostty";
          run = "move-node-to-workspace 1";
        }
      ];
      mode.main.binding = {
        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";

        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        alt-minus = "resize smart -50";
        alt-equal = "resize smart +50";

        alt-slash = "layout tiles horizontal vertical";
        alt-comma = "layout accordion horizontal vertical";
        ctrl-alt-f = "fullscreen";
        alt-shift-space = "layout floating tiling";
        alt-enter = "exec-and-forget open -na Ghostty";

        alt-1 = "workspace 1";
        alt-2 = "workspace 2";
        alt-3 = "workspace 3";
        alt-4 = "workspace 4";
        alt-5 = "workspace 5";
        alt-6 = "workspace 6";
        alt-7 = "workspace 7";
        alt-8 = "workspace 8";
        alt-9 = "workspace 9";
        alt-a = "workspace A";
        alt-b = "workspace B";
        alt-c = "workspace C";
        alt-d = "workspace D";
        alt-e = "workspace E";
        alt-f = "workspace F";

        alt-shift-1 = "move-node-to-workspace 1";
        alt-shift-2 = "move-node-to-workspace 2";
        alt-shift-3 = "move-node-to-workspace 3";
        alt-shift-4 = "move-node-to-workspace 4";
        alt-shift-5 = "move-node-to-workspace 5";
        alt-shift-6 = "move-node-to-workspace 6";
        alt-shift-7 = "move-node-to-workspace 7";
        alt-shift-8 = "move-node-to-workspace 8";
        alt-shift-9 = "move-node-to-workspace 9";
        alt-shift-a = "move-node-to-workspace A";
        alt-shift-b = "move-node-to-workspace B";
        alt-shift-c = "move-node-to-workspace C";
        alt-shift-d = "move-node-to-workspace D";
        alt-shift-e = "move-node-to-workspace E";
        alt-shift-f = "move-node-to-workspace F";

        alt-tab = "workspace-back-and-forth";
        alt-shift-tab = "move-workspace-to-monitor --wrap-around next";
      };
    };
  };

  # Broken: https://github.com/nix-darwin/nix-darwin/issues/1041
  # services.karabiner-elements.enable = true;

  services.tailscale = {
    enable = true;
    overrideLocalDns = true;
  };

  services.jankyborders = {
    enable = true;
    active_color = "gradient(top_left=0xffbd93f9,bottom_right=0xffff79c6)";
    width = 5.0;
  };

  launchd.user.agents = {
    nixos-vm = {
      serviceConfig = {
        Label = "com.user.nixos-vm";
        ProgramArguments = ["/Applications/UTM.app/Contents/MacOS/utmctl" "start" "mini-nix"];
        RunAtLoad = true;
        StandardOutPath = "/tmp/utm/nixos-vim.log";
        StandardErrorPath = "/tmp/utm/nixos-vim.err";
      };
    };
    immich-backup-sync = {
      serviceConfig = {
        Label = "com.user.immich-backup-sync";
        ProgramArguments = [
          "${pkgs.writeShellScript "immich-backup-sync" ''
            if ! ${pkgs.rsync}/bin/rsync -rv \
              --omit-dir-times \
              --no-perms \
              --no-group \
              --no-owner \
              "backup@mini-nix:borg-immich" \
              "/Volumes/Samsung T3/backups/"; then
              ${pkgs.ntfy-sh}/bin/ntfy publish \
                --title "Backup Failed" \
                --priority high \
                --tags warning \
                "http://mini-nix:8080/backups" "immich-backup-sync failed on mini-me"
              exit 1
            fi
          ''}"
        ];
        StartCalendarInterval = [
          {
            Hour = 19;
            Minute = 0;
          }
        ];
        StandardOutPath = "/tmp/immich-backup-sync.log";
        StandardErrorPath = "/tmp/immich-backup-sync.err";
      };
    };
  };

  system = {
    checks.verifyNixPath = false;
    primaryUser = user;
    stateVersion = 5;

    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        # 120, 90, 60, 30, 12, 6, 2
        KeyRepeat = 2;

        # 120, 94, 68, 35, 25, 15
        InitialKeyRepeat = 15;

        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
      };

      dock = {
        autohide = true;
        show-recents = false;
        tilesize = 48;
      };

      finder = {
        AppleShowAllExtensions = true;
      };

      screencapture.location = "~/Pictures/screenshots";

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
  };
}
