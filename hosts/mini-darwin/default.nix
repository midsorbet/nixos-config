{
  agenix,
  config,
  lib,
  pkgs,
  paneru,
  ...
}: let
  user = "me";
  homeDir = config.hjem.users.${user}.directory;
  baymaxLanAddress = "192.168.4.200";
  dactylKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAkcCO74k1FF3rHzIfX07QdaJXpOqyl3tUdLguL0kJzc dactyl";
  ompBrokerLocalPort = 18765;
  ompBrokerRemotePort = 8765;
  baymaxKnownHosts = pkgs.writeText "baymax-known-hosts" ''
    ${baymaxLanAddress} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAx1gSRAypT/nq3PKlK54lGTJDPNM2QeK25QoBt0UNPD
  '';
  # Mini's existing age/SSH identity is already authorized on Baymax.
  # Use Apple's stable signed client directly: background Nix-store binaries
  # have no Local Network privacy grant and fail LAN connections with EHOSTUNREACH.
  ompAuthBrokerTunnelArguments = [
    "/usr/bin/ssh"
    "-F"
    "/dev/null"
    "-N"
    "-T"
    "-i"
    "${homeDir}/.ssh/id_ed25519"
    "-o"
    "BatchMode=yes"
    "-o"
    "ConnectTimeout=10"
    "-o"
    "ExitOnForwardFailure=yes"
    "-o"
    "GlobalKnownHostsFile=/dev/null"
    "-o"
    "IdentitiesOnly=yes"
    "-o"
    "LogLevel=ERROR"
    "-o"
    "KbdInteractiveAuthentication=no"
    "-o"
    "PasswordAuthentication=no"
    "-o"
    "PreferredAuthentications=publickey"
    "-o"
    "ServerAliveCountMax=3"
    "-o"
    "ServerAliveInterval=30"
    "-o"
    "StrictHostKeyChecking=yes"
    "-o"
    "UpdateHostKeys=no"
    "-o"
    "UserKnownHostsFile=${baymaxKnownHosts}"
    "-L"
    "127.0.0.1:${toString ompBrokerLocalPort}:127.0.0.1:${toString ompBrokerRemotePort}"
    "${user}@${baymaxLanAddress}"
  ];
in {
  imports = [
    ./secrets.nix
    ../../modules/darwin/anki.nix
    ../../modules/darwin/grayjay.nix
    ../../modules/darwin/mole.nix
    ../../modules/github-cli.nix
    ../../modules/ghostty.nix
    ../../modules/herdr.nix
    ../../modules/hunk.nix
    ../../modules/neovim.nix
    ../../modules/omp
    ../../modules/plannotator.nix
    ../../modules/shared
    agenix.darwinModules.default
    paneru.darwinModules.paneru
  ];

  # nix-darwin manual generation currently calls a removed nixos-render-docs
  # --toc-depth flag with nixpkgs 2026-07-05. Its uninstaller package evaluates
  # a separate default system that still builds the broken manual, so omit both.
  documentation.enable = false;
  system.tools.darwin-uninstaller.enable = false;

  users.users.${user} = {
    name = "${user}";
    home = "/Users/${user}";
    isHidden = false;
    openssh.authorizedKeys.keys = [dactylKey];
  };

  local.anki.enable = true;
  local.git = {
    enable = true;
    inherit user;
    settings = {
      core.pager = "hunk pager";
      "includeIf \"gitdir:${homeDir}/vault/.git/modules/projects/\"" = {
        path = "${homeDir}/.config/git/includes/vault-project-hooks.gitconfig";
      };
    };
    commitSigning.enable = true;
  };
  local.githubCli = {
    enable = true;
    inherit user;
  };
  hjem.users.${user} = {
    files."Projects" = {
      type = "symlink";
      source = "${homeDir}/vault/projects";
      clobber = true;
    };

    xdg.config.files."git/includes/vault-project-hooks.gitconfig" = {
      text = ''
        [core]
          hooksPath = ${homeDir}/vault/.githooks/project
      '';
      clobber = true;
    };
  };
  local.grayjay.enable = true;
  local.ghostty = {
    enable = true;
    inherit user;
  };
  local.herdr = {
    enable = true;
    inherit user;
    remote = {
      enable = true;
      tunnelId = "32cb7364-d8e7-4278-8b5d-25b130e520df";
      credentialsFile = config.age.secrets."herdr-remote-tunnel".path;
      accessAudience = "d1e198782f9611e555c5657c769cb809fb0f1cb56c3a93d187d5fe220f97aee5";
    };
  };
  local.hunk = {
    enable = true;
    inherit user;
  };
  local.mole = {
    enable = true;
    inherit user;
    runPurge = true;
    runOptimize = true;
    cleanCacheCheckouts = true;
    purgePaths = ["~/vault/projects"];
  };
  local.neovim = {
    enable = true;
    inherit user;
  };
  local.omp = {
    enable = true;
    authBrokerUrl = "http://127.0.0.1:${toString ompBrokerLocalPort}";
    collab = {
      enable = true;
      tunnelId = "99c3ef20-b6b7-4dc0-8fee-ee95f1165eeb";
      credentialsFile = config.age.secrets."omp-collab-tunnel".path;
      accessAudience = "0c8cb340a00d4dca1c879dc79a3b7926215f40589c833b9114867b55df4c5033";
    };
  };
  local.plannotator.enable = true;
  local.zsh = {
    enable = true;
    inherit user;
    projectDirectories = ["~/vault/projects"];
    promptTheme = "kanagawa-everforest";
  };

  homebrew = {
    enable = true;
    casks = [
      "calibre"
      "chatgpt"
      {
        name = "cloudflare-warp";
        greedy = true;
      }
      "codex"
      "firefox"
      "ghostty"
      "karabiner-elements"
      "visual-studio-code"
    ];
    onActivation = {
      autoUpdate = true;
      upgrade = true;
    };
  };

  services.openssh = {
    enable = true;
    extraConfig = ''
      PasswordAuthentication no
      KbdInteractiveAuthentication no
      PermitRootLogin no
      AllowUsers ${user}
      TCPKeepAlive yes
      ClientAliveInterval 30
      ClientAliveCountMax 6
    '';
  };

  # Setup user, packages, programs
  nix = {
    package = pkgs.nix;

    settings = {
      # Intentional single-admin trust for local Nix and remote Linux builder workflows.
      trusted-users = ["${user}"];
      substituters = ["https://nix-community.cachix.org" "https://cache.nixos.org"];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    gc = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 2;
        Minute = 0;
      };
      options = "--delete-older-than 7d";
    };

    optimise = {
      automatic = true;
      interval = {
        Weekday = 0;
        Hour = 4;
        Minute = 15;
      };
    };

    extraOptions = ''
      experimental-features = nix-command flakes
      extra-platforms = x86_64-darwin aarch64-darwin
    '';

    buildMachines = [
      {
        hostName = baymaxLanAddress;
        protocol = "ssh-ng";
        systems = ["x86_64-linux"];
        sshUser = "me";
        sshKey = "/etc/nix/baymax-builder-ed25519";
        maxJobs = 4;
        speedFactor = 2;
        supportedFeatures = ["kvm" "benchmark" "big-parallel"];
        publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUF4MWdTUkF5cFQvbnEzUEtsSzU0bEdUSkRQTk0yUWVLMjVRb0J0MFVOUEQK";
      }
    ];

    linux-builder.enable = true;
  };

  # Turn off NIX_PATH warnings now that we're using flakes

  # Load configuration that is shared across systems
  environment.systemPackages =
    [
      agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
      pkgs.mdfried
      pkgs.nh
    ]
    ++ (import ./packages.nix {inherit pkgs;});

  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    NH_FLAKE = "/Users/${user}/vault/projects/nixos-config";
    CODEX_JS_REPL_NODE_PATH = "${pkgs.nodejs}/bin/node";
    # Let terminals provide TERMINFO and fall back to the system database.
    # The default profile-based TERMINFO_DIRS entries may not exist on Darwin.
    TERMINFO_DIRS = lib.mkForce "";
  };

  environment.interactiveShellInit = lib.mkAfter ''
    codex_args=(
      -c 'notify=["/usr/bin/true"]'
      -c 'tui.notifications=["agent-turn-complete"]'
      -c 'tui.notification_condition="always"'
      -c 'tui.notification_method="osc9"'
    )

    ca() {
      command codex "''${codex_args[@]}" "$@"
    }

    cax() {
      PATH="${pkgs.nodejs}/bin:$PATH" \
        AUBE_PARANOID=true \
        aube dlx --package @openai/codex codex "''${codex_args[@]}" "$@"
    }
  '';

  networking.knownNetworkServices = [
    "Ethernet"
    "Thunderbolt Bridge"
    "Wi-Fi"
  ];

  launchd.user.agents.omp-auth-broker-tunnel = {
    serviceConfig = {
      ProgramArguments = ompAuthBrokerTunnelArguments;
      RunAtLoad = true;
      KeepAlive = true;
      ProcessType = "Background";
      StandardErrorPath = "${homeDir}/Library/Logs/omp-auth-broker-tunnel.err.log";
      StandardOutPath = "${homeDir}/Library/Logs/omp-auth-broker-tunnel.out.log";
      ThrottleInterval = 10;
    };
  };

  programs.ssh.extraConfig = ''
    Host *
      SendEnv LANG LC_*
      HashKnownHosts yes
      ServerAliveInterval 30
      ServerAliveCountMax 6
      TCPKeepAlive yes

    Host github.com
      IdentitiesOnly yes
      IdentityFile /Users/${user}/.ssh/id_github
  '';

  programs.tmux = {
    enable = true;
    enableMouse = true;
  };

  services.paneru = {
    enable = true;
    settings = {
      options = {
        focus_follows_mouse = false;
        mouse_follows_focus = true;
        preset_column_widths = [0.5 0.66 0.75 1.0];
        window_resize_cycle = false;
        # Numbered virtual workspace rows are created on demand and remain stable.
        reap_empty_workspaces = false;
        animation_speed = 15.0;
        auto_center = false;
        sliver_width = 5;
        sliver_height = 1.0;
        # The portrait display is logically below the landscape display.
        horizontal_mouse_warp = -1;
      };
      padding = {
        top = 5;
        bottom = 5;
        left = 5;
        right = 5;
      };
      swipe = {
        sensitivity = 0.35;
        deceleration = 4.0;
        continuous = false;
        scroll.modifier = "alt";
        scroll.vertical_modifier = "shift";
      };
      bindings = {
        window_focus_west = "alt - h";
        window_focus_south = "alt - j";
        window_focus_north = "alt - k";
        window_focus_east = "alt - l";
        window_focus_managed = "alt - tab";
        window_focus_unmanaged = "ctrl + alt - tab";
        window_raise_floating = "ctrl + alt - space";

        window_swap_west = "alt + shift - h";
        window_swap_south = "alt + shift - j";
        window_swap_north = "alt + shift - k";
        window_swap_east = "alt + shift - l";

        window_virtual_north = "ctrl + alt - k";
        window_virtual_south = "ctrl + alt - j";
        window_virtualmove_north = "ctrl + alt + shift - k";
        window_virtualmove_south = "ctrl + alt + shift - j";

        window_virtualnum_1 = "alt - 1";
        window_virtualnum_2 = "alt - 2";
        window_virtualnum_3 = "alt - 3";
        window_virtualnum_4 = "alt - 4";
        window_virtualnum_5 = "alt - 5";
        window_virtualnum_6 = "alt - 6";
        window_virtualnum_7 = "alt - 7";
        window_virtualnum_8 = "alt - 8";
        window_virtualnum_9 = "alt - 9";

        window_virtualsendnum_1 = "alt + shift - 1";
        window_virtualsendnum_2 = "alt + shift - 2";
        window_virtualsendnum_3 = "alt + shift - 3";
        window_virtualsendnum_4 = "alt + shift - 4";
        window_virtualsendnum_5 = "alt + shift - 5";
        window_virtualsendnum_6 = "alt + shift - 6";
        window_virtualsendnum_7 = "alt + shift - 7";
        window_virtualsendnum_8 = "alt + shift - 8";
        window_virtualsendnum_9 = "alt + shift - 9";

        window_shrink = "alt - minus";
        window_grow = "alt - equal";
        window_center = "alt - c";
        window_fullwidth = "ctrl + alt - f";
        window_manage = "alt + shift - space";

        window_unstack = "alt - slash";
        window_stack = "alt - comma";
        window_balance = "alt - b";

        window_nextdisplay = "alt + shift - tab";
        window_snap = "alt - s";
        quit = "ctrl + alt - q";
      };
      windows = {
        system_settings = {
          title = ".*";
          bundle_id = "com.apple.systempreferences";
          floating = true;
        };
        chatgpt_browser_comment = {
          title = "^Browser comment$";
          bundle_id = "com.openai.codex";
          floating = true;
        };
        renpho_health = {
          title = ".*";
          bundle_id = "com.renpho.health";
          floating = true;
        };
      };
    };
  };

  # Broken: https://github.com/nix-darwin/nix-darwin/issues/1041
  # services.karabiner-elements.enable = true;

  services.jankyborders = {
    enable = true;
    active_color = "gradient(top_left=0xffbd93f9,bottom_right=0xffff79c6)";
    width = 5.0;
  };

  system = {
    checks.verifyNixPath = false;
    primaryUser = user;
    stateVersion = 5;

    activationScripts.postActivation.text = lib.mkAfter ''
      set -eu

      credentials='${config.age.secrets."mini-warp-service-token".path}'
      directory='/Library/Application Support/Cloudflare'
      target="$directory/mdm.xml"
      warp_cli='/Applications/Cloudflare WARP.app/Contents/Resources/warp-cli'
      warp_user=${lib.escapeShellArg user}

      remaining=30
      while [ ! -s "$credentials" ]; do
        if [ "$remaining" -eq 0 ]; then
          echo "Timed out waiting for agenix to decrypt the Cloudflare WARP enrollment token" >&2
          exit 1
        fi
        /bin/sleep 1
        remaining=$((remaining - 1))
      done

      /usr/bin/install -d -m 0755 -o root -g wheel "$directory"

      client_id="$(${pkgs.jq}/bin/jq -er '.client_id | select(test("^[0-9a-f]{32}\\.access$"))' "$credentials")"
      client_secret="$(${pkgs.jq}/bin/jq -er '.client_secret | select(test("^[0-9a-f]{64}$"))' "$credentials")"

      tmp_xml="$(/usr/bin/mktemp "$directory/.mdm.XXXXXX.xml")"
      trap '/bin/rm -f "$tmp_xml"' EXIT

      /bin/cat >"$tmp_xml" <<EOF
      <dict>
        <key>configs</key>
        <array>
          <dict>
            <key>display_name</key>
            <string>Mini service enrollment</string>
            <key>organization</key>
            <string>midsorbet</string>
            <key>auth_client_id</key>
            <string>$client_id</string>
            <key>auth_client_secret</key>
            <string>$client_secret</string>
            <key>service_mode</key>
            <string>warp</string>
            <key>auto_connect</key>
            <integer>1</integer>
            <key>switch_locked</key>
            <false/>
            <key>onboarding</key>
            <false/>
            <key>enable_pmtud</key>
            <false/>
          </dict>
        </array>
        <key>organization_configs</key>
        <dict>
          <key>midsorbet</key>
          <dict>
            <key>hardware_backed_registration</key>
            <true/>
          </dict>
        </dict>
      </dict>
      EOF

      /usr/sbin/chown root:wheel "$tmp_xml"
      /bin/chmod 0600 "$tmp_xml"

      if [ ! -f "$target" ] || ! /usr/bin/cmp -s "$tmp_xml" "$target"; then
        /bin/mv -f "$tmp_xml" "$target"
      fi

      if [ ! -x "$warp_cli" ]; then
        echo "Cloudflare One Client CLI is missing after Homebrew activation" >&2
        exit 1
      fi

      /usr/bin/sudo -H -u "$warp_user" -- "$warp_cli" mdm refresh
      /usr/bin/sudo -H -u "$warp_user" -- "$warp_cli" mdm set-config 'Mini service enrollment'
    '';

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
