{
  config,
  herdr,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.herdr;
  tomlFormat = pkgs.formats.toml {};
  yamlFormat = pkgs.formats.yaml {};
  remotePackage = pkgs.callPackage ../packages/herdr-remote.nix {};

  integrationHelper = pkgs.writeShellScriptBin "herdr-install-agent-integrations" ''
    set -euo pipefail

    ${lib.getExe cfg.package} integration install codex
    ${lib.getExe cfg.package} integration install omp
    ${lib.getExe cfg.package} integration status
  '';

  remoteHome = "/Users/${cfg.user}";
  remoteLogDirectory = "${remoteHome}/Library/Logs/herdr-remote";
  remoteOrigin = "https://${cfg.remote.hostname}";
  tunnelConfig = yamlFormat.generate "herdr-remote-cloudflared.yml" {
    tunnel = cfg.remote.tunnelId;
    "credentials-file" = cfg.remote.credentialsFile;
    ingress = [
      {
        hostname = cfg.remote.hostname;
        service = "http://127.0.0.1:${toString cfg.remote.port}";
        originRequest.access = {
          required = true;
          teamName = cfg.remote.accessTeamName;
          audTag = [cfg.remote.accessAudience];
        };
      }
      {service = "http_status:404";}
    ];
  };

  relayRunner = pkgs.writeShellApplication {
    name = "herdr-remote-relay-runner";
    text = ''
      set -euo pipefail

      export HOME=${lib.escapeShellArg remoteHome}
      export HERDR_BIN=${lib.escapeShellArg (lib.getExe cfg.package)}
      export HERDR_LOG_DIR=${lib.escapeShellArg remoteLogDirectory}
      export HERDR_RELAY_BIND=127.0.0.1
      export HERDR_RELAY_PORT=${toString cfg.remote.port}
      export HERDR_RELAY_READ_ONLY=1
      export HERDR_REQUIRE_ACCESS_JWT=1
      export HERDR_ALLOWED_ORIGIN=${lib.escapeShellArg remoteOrigin}
      export HERDR_MAX_CLIENTS=${toString cfg.remote.maxClients}
      export HERDR_MAX_CONNECTION_SECONDS=${toString cfg.remote.maxConnectionSeconds}
      export HERDR_MDNS=0

      mkdir -p "$HERDR_LOG_DIR"
      exec >>"$HERDR_LOG_DIR/relay.out.log" 2>>"$HERDR_LOG_DIR/relay.err.log"
      exec ${lib.getExe cfg.remote.package}
    '';
  };

  tunnelRunner = pkgs.writeShellApplication {
    name = "herdr-remote-tunnel-runner";
    text = ''
      set -euo pipefail

      mkdir -p ${lib.escapeShellArg remoteLogDirectory}
      exec ${lib.getExe pkgs.cloudflared} tunnel \
        --no-autoupdate \
        --loglevel info \
        --logfile ${lib.escapeShellArg "${remoteLogDirectory}/tunnel.log"} \
        --config ${lib.escapeShellArg tunnelConfig} \
        run ${lib.escapeShellArg cfg.remote.tunnelId}
    '';
  };

  remoteStart = pkgs.writeShellApplication {
    name = "herdr-remote-start";
    runtimeInputs = [pkgs.curl];
    text = ''
      set -euo pipefail

      credentials=${lib.escapeShellArg cfg.remote.credentialsFile}
      if [[ ! -r "$credentials" ]]; then
        echo "Herdr Remote tunnel credentials are not readable: $credentials" >&2
        exit 1
      fi

      domain="gui/$(/usr/bin/id -u)"
      relay_label="$domain/org.nixos.herdr-remote-relay"
      tunnel_label="$domain/org.nixos.herdr-remote-tunnel"

      /bin/launchctl kickstart -k "$relay_label"

      attempts=0
      until curl --fail --silent --show-error \
        "http://127.0.0.1:${toString cfg.remote.port}/healthz" >/dev/null; do
        attempts=$((attempts + 1))
        if [[ "$attempts" -ge 30 ]]; then
          echo "Herdr Remote relay did not become ready" >&2
          exit 1
        fi
        /bin/sleep 1
      done

      /bin/launchctl kickstart -k "$tunnel_label"
      echo "Herdr Remote started at ${remoteOrigin}"
    '';
  };

  remoteStop = pkgs.writeShellApplication {
    name = "herdr-remote-stop";
    text = ''
      set -euo pipefail

      domain="gui/$(/usr/bin/id -u)"
      /bin/launchctl kill SIGTERM "$domain/org.nixos.herdr-remote-tunnel" 2>/dev/null || true
      /bin/launchctl kill SIGTERM "$domain/org.nixos.herdr-remote-relay" 2>/dev/null || true
      echo "Herdr Remote stopped"
    '';
  };

  remoteStatus = pkgs.writeShellApplication {
    name = "herdr-remote-status";
    runtimeInputs = [pkgs.curl];
    text = ''
      set -euo pipefail

      domain="gui/$(/usr/bin/id -u)"
      /bin/launchctl print "$domain/org.nixos.herdr-remote-relay" || true
      /bin/launchctl print "$domain/org.nixos.herdr-remote-tunnel" || true
      curl --fail --silent --show-error \
        "http://127.0.0.1:${toString cfg.remote.port}/healthz" || true
    '';
  };
in {
  options.local.herdr = {
    enable = lib.mkEnableOption "Herdr terminal agent multiplexer";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed Herdr package and config.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
      description = "Herdr package to install.";
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {
        onboarding = false;

        update = {
          channel = "stable";
          version_check = false;
          manifest_check = true;
        };

        terminal = {
          default_shell = "zsh";
          shell_mode = "auto";
          new_cwd = "follow";
        };

        remote.manage_ssh_config = true;

        keys = {
          prefix = "ctrl+b";
          detach = "prefix+q";
          switch_tab = "prefix+1..9";
          switch_workspace = "prefix+shift+1..9";
          focus_agent = "prefix+alt+1..9";
        };

        theme = {
          name = "kanagawa";
          auto_switch = true;
          light_name = "terminal";
          dark_name = "kanagawa";
        };

        ui = {
          mouse_capture = true;
          pane_scrollbars = false;
          copy_on_select = true;
          sidebar_width = 20;
          sidebar_min_width = 18;
          sidebar_max_width = 24;
          sidebar = {
            agents = {
              row_gap = 0;
              rows = [["state_icon" "workspace" "tab"]];
            };
            spaces = {
              row_gap = 0;
              rows = [["state_icon" "workspace" "branch" "git_status"]];
            };
          };
          toast = {
            delivery = "terminal";
            delay_seconds = 1;
            herdr.position = "bottom-right";
            clipboard = {
              enabled = true;
              position = "bottom-center";
            };
          };
        };

        session.resume_agents_on_restore = true;

        experimental = {
          allow_nested = false;
          pane_history = true;
          kitty_graphics = true;
        };
      };
      description = "Herdr TOML configuration written to the user's XDG config directory.";
    };

    installCodexSkill = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Herdr's agent skill into the user's Codex skills directory.";
    };

    installOmpExtension = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Herdr's OMP agent-state extension into the user's OMP agent directory.";
    };

    remote = {
      enable = lib.mkEnableOption "hardened read-only Herdr browser relay";

      package = lib.mkOption {
        type = lib.types.package;
        default = remotePackage;
        description = "Pinned and hardened Herdr Remote relay package.";
      };

      hostname = lib.mkOption {
        type = lib.types.str;
        default = "herdr.midsorbet.me";
        description = "Cloudflare Access hostname for the relay.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 18375;
        description = "Loopback port used by the relay and Cloudflare Tunnel.";
      };

      maxClients = lib.mkOption {
        type = lib.types.ints.positive;
        default = 2;
        description = "Maximum simultaneous browser WebSocket clients.";
      };

      maxConnectionSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1800;
        description = "Hard maximum WebSocket lifetime, capped further by the Access JWT expiry.";
      };

      tunnelId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Cloudflare Tunnel UUID.";
      };

      credentialsFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Path to the agenix-managed per-tunnel credentials JSON.";
      };

      accessTeamName = lib.mkOption {
        type = lib.types.str;
        default = "midsorbet";
        description = "Cloudflare Access team name used for origin-side JWT validation.";
      };

      accessAudience = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Cloudflare Access application audience tag validated by cloudflared.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.optionals cfg.remote.enable [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "local.herdr.remote is only supported on Darwin.";
      }
      {
        assertion = cfg.remote.tunnelId != "";
        message = "local.herdr.remote.tunnelId must be set.";
      }
      {
        assertion = cfg.remote.credentialsFile != "";
        message = "local.herdr.remote.credentialsFile must be set.";
      }
      {
        assertion = cfg.remote.accessAudience != "";
        message = "local.herdr.remote.accessAudience must be set.";
      }
    ];

    hjem.users.${cfg.user} = {
      packages =
        [cfg.package integrationHelper]
        ++ lib.optionals cfg.remote.enable [
          cfg.remote.package
          remoteStart
          remoteStop
          remoteStatus
        ];

      xdg.config.files."herdr/config.toml" = lib.mkIf (cfg.settings != {}) {
        source = tomlFormat.generate "herdr-config.toml" cfg.settings;
        clobber = true;
      };

      files = lib.mkMerge [
        (lib.mkIf cfg.installCodexSkill {
          ".codex/skills/herdr/SKILL.md" = {
            source = "${herdr}/SKILL.md";
            clobber = true;
          };
        })

        (lib.mkIf cfg.installOmpExtension {
          ".omp/agent/extensions/herdr-omp-agent-state.ts" = {
            source = "${herdr}/src/integration/assets/omp/herdr-agent-state.ts";
            clobber = true;
          };
        })
      ];
    };

    launchd.user.agents = lib.mkIf cfg.remote.enable {
      herdr-remote-relay = {
        command = lib.getExe relayRunner;
        serviceConfig = {
          RunAtLoad = false;
          KeepAlive = false;
          ProcessType = "Background";
        };
      };

      herdr-remote-tunnel = {
        command = lib.getExe tunnelRunner;
        serviceConfig = {
          RunAtLoad = false;
          KeepAlive = false;
          ProcessType = "Background";
        };
      };
    };
  };
}
