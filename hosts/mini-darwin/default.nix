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
  miniEthernetLanAddress = "192.168.4.194";
  miniEthernetLanIpv6Address = "fdef:bd26:b58e:1:1412:ff96:d77a:51e6";
  miniWarpDnsDriftCheck = pkgs.writeShellApplication {
    name = "mini-warp-dns-drift-check";
    runtimeInputs = [pkgs.bind pkgs.gawk];
    text = ''
      set -euo pipefail

      compare_mini_warp_dns_addresses() {
        live_warp_ipv4="$1"
        mini_warp_dns_ipv4="$2"

        if [ "$live_warp_ipv4" != "$mini_warp_dns_ipv4" ]; then
          echo "Mini WARP DNS drift: active interface IP $live_warp_ipv4 does not match mini.warp.midsorbet.me A record $mini_warp_dns_ipv4. Update Gateway DNS rule 15db1de9-c0f1-4e7d-94e2-741938ee194b before using WARP SSH." >&2
          return 1
        fi

        echo "Mini WARP DNS drift check passed: mini.warp.midsorbet.me resolves to $live_warp_ipv4"
      }

      if [ "''${1:-}" = "--compare" ]; then
        if [ "$#" -ne 3 ]; then
          echo "Mini WARP DNS drift check usage: mini-warp-dns-drift-check --compare LIVE_WARP_IPV4 DNS_IPV4" >&2
          exit 2
        fi
        compare_mini_warp_dns_addresses "$2" "$3"
        exit
      fi

      if [ "$#" -ne 0 ]; then
        echo "Mini WARP DNS drift check usage: mini-warp-dns-drift-check [--compare LIVE_WARP_IPV4 DNS_IPV4]" >&2
        exit 2
      fi

      attempt=0
      live_warp_ipv4=""
      mini_warp_dns_ipv4=""
      while [ "$attempt" -lt 30 ]; do
        live_warp_ipv4="$(
          /sbin/ifconfig | awk '
            $1 == "inet" {
              split($2, octets, ".")
              if (octets[1] == 100 && octets[2] >= 96 && octets[2] <= 111) {
                print $2
                exit
              }
            }
          '
        )"
        mini_warp_dns_ipv4="$(
          dig @127.0.2.2 mini.warp.midsorbet.me A +short +time=2 +tries=1 \
            | awk '/^[0-9]+(\.[0-9]+){3}$/ { print; exit }'
        )"

        if [ -n "$live_warp_ipv4" ] && [ -n "$mini_warp_dns_ipv4" ]; then
          compare_mini_warp_dns_addresses "$live_warp_ipv4" "$mini_warp_dns_ipv4"
          exit
        fi

        attempt=$((attempt + 1))
        /bin/sleep 1
      done

      if [ -z "$live_warp_ipv4" ]; then
        echo "Mini WARP DNS drift check unavailable: no active 100.96.0.0/12 interface address appeared within 30 seconds" >&2
      else
        echo "Mini WARP DNS drift check unavailable: mini.warp.midsorbet.me returned no IPv4 answer through the WARP resolver within 30 seconds" >&2
      fi
      exit 1
    '';
  };
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
    "-L"
    "127.0.0.1:22000:127.0.0.1:22000"
    "-R"
    "127.0.0.1:11434:127.0.0.1:11434"
    "${user}@${baymaxLanAddress}"
  ];
in {
  imports = [
    ./secrets.nix
    ../../modules/darwin/anki.nix
    ../../modules/darwin/grayjay.nix
    ../../modules/darwin/mole.nix
    ../../modules/darwin/ollama.nix
    ../../modules/darwin/syncthing.nix
    ../../modules/github-cli.nix
    ../../modules/ghostty.nix
    ../../modules/herdr.nix
    ../../modules/hunk.nix
    (import ../../modules/local-lan-dns-resolver.nix {platform = "darwin";})
    ../../modules/neovim
    ../../modules/omp
    ../../modules/plannotator.nix
    ../../modules/shared-agent-skills.nix
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
  local.ollama.enable = true;
  local.syncthing = {
    enable = true;
    certFile = config.age.secrets."syncthing-mini-cert".path;
    keyFile = config.age.secrets."syncthing-mini-key".path;
    peerDeviceId = "O53AQ2K-UWUX2VE-VD5BPYR-TK66WA4-SDDHEMU-YRKJVA5-4U3ZSH6-L27BFQF";
  };
  local.atuin = {
    enable = true;
    inherit user;
  };
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

    files.".finicky.js" = {
      text = ''
        export default {
          defaultBrowser: "Firefox",
          options: {
            checkForUpdates: false,
            hideIcon: true,
            logRequests: false,
          },
          handlers: [
            {
              // matchHostnames treats strings as exact hostnames. These anchored
              // expressions cover each apex hostname and all of its subdomains.
              match: finicky.matchHostnames([
                /(^|\.)x\.com$/,
                /(^|\.)twitter\.com$/,
                /(^|\.)reddit\.com$/,
                /(^|\.)redd\.it$/,
              ]),
              browser: "Helium",
            },
          ],
        };
      '';
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
  };
  local.hunk = {
    enable = true;
    inherit user;
  };
  local.lanDnsResolver = {
    enable = true;
    listenAddresses = [miniEthernetLanAddress miniEthernetLanIpv6Address];
  };
  local.mole = {
    enable = true;
    inherit user;
  };
  local.neovim = {
    enable = true;
    inherit user;
  };
  local.omp = {
    enable = true;
    authBrokerUrl = "http://127.0.0.1:${toString ompBrokerLocalPort}";
    hister = {
      enable = true;
      environmentFile = config.age.secrets."hister-env".path;
    };
    collab = {
      enable = true;
      displayName = "mini-me";
      tunnelId = "99c3ef20-b6b7-4dc0-8fee-ee95f1165eeb";
      credentialsFile = config.age.secrets."omp-collab-tunnel".path;
      accessAudience = "0c8cb340a00d4dca1c879dc79a3b7926215f40589c833b9114867b55df4c5033";
      idleTimeoutSeconds = 8 * 60 * 60;
      maxConnectionSeconds = 8 * 60 * 60;
    };
  };
  local.plannotator.enable = true;
  local.sharedAgentSkills.enable = true;
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
      "finicky"
      "firefox"
      "ghostty"
      "helium-browser"
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

    linux-builder = {
      enable = true;
      # macOS 27 HVF rejects nixpkgs' default GICv2 machine; this later QEMU option overrides it.
      config.virtualisation.qemu.options = ["-machine gic-version=3"];
    };
  };

  # Turn off NIX_PATH warnings now that we're using flakes

  # Load configuration that is shared across systems
  environment.systemPackages =
    [
      agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
      miniWarpDnsDriftCheck
      pkgs.hister
      pkgs.mdfried
      pkgs.nh
    ]
    ++ (import ./packages.nix {inherit pkgs;});

  environment.variables = {
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

  # Start Helium with OMP's browser relay extension. Keep a normal startup
  # window so Paneru observes and tiles Helium when it launches at login.
  launchd.user.agents.helium-omp-browser-relay = {
    serviceConfig = {
      ProgramArguments = [
        "/Applications/Helium.app/Contents/MacOS/Helium"
        "--load-extension=${homeDir}/.omp/browser-relay/extension"
      ];
      RunAtLoad = true;
      ProcessType = "Interactive";
    };
  };
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

      for ssh_firewall_app in \
        /usr/libexec/sshd-keygen-wrapper \
        /usr/sbin/sshd \
        /usr/libexec/sshd-auth \
        /usr/libexec/sshd-session; do
        /usr/libexec/ApplicationFirewall/socketfilterfw --remove "$ssh_firewall_app" >/dev/null 2>&1 || true
        /usr/libexec/ApplicationFirewall/socketfilterfw --add "$ssh_firewall_app"
        /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$ssh_firewall_app"
      done
      firefox_preferences=/Library/Preferences/org.mozilla.firefox
      /usr/bin/defaults write "$firefox_preferences" EnterprisePoliciesEnabled -bool true
      /usr/bin/defaults write "$firefox_preferences" Extensions__Install -array \
        'https://addons.mozilla.org/firefox/downloads/latest/hister/latest.xpi' \
        'https://addons.mozilla.org/firefox/downloads/latest/clearurls/latest.xpi'
      /usr/sbin/chown root:wheel "$firefox_preferences.plist"
      /bin/chmod 0644 "$firefox_preferences.plist"
      /bin/rm -f '/Library/Application Support/Mozilla/policies.json'


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

      /bin/rm -f "$directory/.mdm.XXXXXX.xml"
      tmp_xml="$(/usr/bin/mktemp "$directory/.mdm.xml.XXXXXX")"
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

      # Homebrew cask upgrades have twice replaced Mini's WARP registration. Check both
      # immediately and after the observed delayed re-registration window. Report drift
      # without aborting activation: the cask update that causes drift must still deploy.
      ${lib.getExe miniWarpDnsDriftCheck} || true
      /bin/sleep 15
      ${lib.getExe miniWarpDnsDriftCheck} || true
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
