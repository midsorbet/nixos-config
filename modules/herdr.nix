{
  config,
  herdr,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.herdr;
  tomlFormat = pkgs.formats.toml {};
  herdrRemoteRev = "221e2fe71d1e9f8e09f1a7b2211157c53d31ce1f";
  herdrRemoteSrc = pkgs.fetchFromGitHub {
    owner = "dcolinmorgan";
    repo = "herdr-remote";
    rev = herdrRemoteRev;
    hash = "sha256-S1Aq/5ZgMHwqDMcjEdvZAUgY+VMyzDTSuIzNEZEdNfo=";
  };

  integrationHelper = pkgs.writeShellScriptBin "herdr-install-agent-integrations" ''
    set -euo pipefail

    ${lib.getExe cfg.package} integration install codex
    ${lib.getExe cfg.package} integration install omp
    ${lib.getExe cfg.package} integration status
  '';

  quickTunnelHelper = pkgs.writeShellApplication {
    name = "herdr-remote-quick-tunnel";
    runtimeInputs = [
      pkgs.cloudflared
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.perl
      pkgs.uv
      pkgs.xkcdpass
    ];
    text = ''
      usage() {
        cat <<'EOF'
      usage: herdr-remote-quick-tunnel [PORT]

      Starts a local herdr-remote relay and exposes it through a temporary
      Cloudflare Quick Tunnel. Stop with Ctrl-C to tear down the public URL.

      Environment:
        HERDR_RELAY_PORT   Relay listen port, default 18375.
        HERDR_RELAY_TOKEN  Optional pre-set relay token. If unset, generated
                           as a five-word hyphenated passphrase.
      EOF
      }

      case "''${1:-}" in
        -h|--help)
          usage
          exit 0
          ;;
        "")
          port="''${HERDR_RELAY_PORT:-18375}"
          ;;
        *)
          port="$1"
          ;;
      esac

      case "$port" in
        ""|*[!0-9]*)
          echo "error: PORT must be numeric" >&2
          exit 2
          ;;
      esac

      token="''${HERDR_RELAY_TOKEN:-}"
      if [ -z "$token" ]; then
        token="$(xkcdpass -n 5 -d '-' -C lower)"
      fi

      workdir="$(mktemp -d "''${TMPDIR:-/tmp}/herdr-remote-quick.XXXXXX")"
      relay_pid=""
      tunnel_pid=""

      cleanup() {
        set +e
        if [ -n "$tunnel_pid" ] && kill -0 "$tunnel_pid" 2>/dev/null; then
          kill "$tunnel_pid" 2>/dev/null
          wait "$tunnel_pid" 2>/dev/null
        fi
        if [ -n "$relay_pid" ] && kill -0 "$relay_pid" 2>/dev/null; then
          kill "$relay_pid" 2>/dev/null
          wait "$relay_pid" 2>/dev/null
        fi
        rm -rf "$workdir"
      }

      trap cleanup EXIT
      trap 'exit 130' INT
      trap 'exit 143' TERM

      relay="$workdir/herdr_relay.py"
      cp ${herdrRemoteSrc}/relay/herdr_relay.py "$relay"

      # Keep the relay local-only and avoid mDNS cleanup hangs in the upstream prototype.
      perl -0pi -e 's/zc, info = start_mdns\(\)/zc, info = (None, None)/' "$relay"
      perl -0pi -e 's/serve\(handle_client, "0\.0\.0\.0", WS_PORT, process_request=process_request\)/serve(handle_client, "127.0.0.1", WS_PORT, process_request=process_request)/' "$relay"

      HERDR_BIN="${lib.getExe cfg.package}" \
        HERDR_RELAY_PORT="$port" \
        HERDR_RELAY_TOKEN="$token" \
        uv run "$relay" >"$workdir/relay.log" 2>&1 &
      relay_pid="$!"

      relay_ready=""
      for _ in $(seq 1 60); do
        if curl -fsS --max-time 1 "http://127.0.0.1:$port/?token=$token" >/dev/null 2>&1; then
          relay_ready=1
          break
        fi
        if ! kill -0 "$relay_pid" 2>/dev/null; then
          echo "error: herdr-remote relay exited during startup" >&2
          cat "$workdir/relay.log" >&2
          exit 1
        fi
        sleep 0.5
      done

      if [ -z "$relay_ready" ]; then
        echo "error: herdr-remote relay did not become ready on 127.0.0.1:$port" >&2
        cat "$workdir/relay.log" >&2
        exit 1
      fi

      cloudflared tunnel --url "http://127.0.0.1:$port" >"$workdir/cloudflared.log" 2>&1 &
      tunnel_pid="$!"

      url=""
      for _ in $(seq 1 120); do
        if ! kill -0 "$tunnel_pid" 2>/dev/null; then
          echo "error: cloudflared exited during startup" >&2
          cat "$workdir/cloudflared.log" >&2
          exit 1
        fi
        url="$(grep -Eo 'https://[-a-zA-Z0-9]+\.trycloudflare\.com' "$workdir/cloudflared.log" | tail -n 1 || true)"
        if [ -n "$url" ]; then
          break
        fi
        sleep 1
      done

      if [ -z "$url" ]; then
        echo "error: timed out waiting for Cloudflare Quick Tunnel URL" >&2
        cat "$workdir/cloudflared.log" >&2
        exit 1
      fi

      ws_url="wss://''${url#https://}"

      cat <<EOF
      herdr-remote quick tunnel is live.

        Web UI:    https://herdr-demo.pages.dev
        Relay URL: $ws_url
        Token:     $token

      Paste the Relay URL and Token into the web UI settings.
      Stop this command with Ctrl-C to tear down the public URL.
      EOF

      while kill -0 "$relay_pid" 2>/dev/null && kill -0 "$tunnel_pid" 2>/dev/null; do
        sleep 5
      done

      echo "herdr-remote quick tunnel stopped" >&2
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
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user} = {
      packages = [cfg.package integrationHelper quickTunnelHelper];

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
  };
}
