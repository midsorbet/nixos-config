{
  config,
  herdr-omp-plugins,
  lib,
  pkgs,
  ...
}: let
  inherit (herdr-omp-plugins.lib.buildersFor pkgs)
    mkRemoteCollabExtension
    mkSpinoffExtension
    ;
  cfg = config.local.omp;
  authBrokerUrlIsSecure =
    cfg.authBrokerUrl
    == null
    || builtins.match "https://.+" cfg.authBrokerUrl != null
    || builtins.match "http://(127\\.0\\.0\\.1|localhost)(:[0-9]+)?(/.*)?" cfg.authBrokerUrl != null;

  assetRevision = "37eee71978951fccf66b21f7e3e2b74596ac9d74";
  assetSrc = pkgs.fetchzip {
    url = "https://github.com/can1357/oh-my-pi/archive/${assetRevision}.tar.gz";
    hash = "sha256-z7rV2HjYEHnMeh8nY/gYM7iDYkOIVTPQJoUbssbROfs=";
  };
  runtimePath =
    lib.makeBinPath ([cfg.pythonPackage cfg.bunPackage cfg.uvPackage cxporterPackage] ++ cfg.extraRuntimePackages);
  computerUsePackage = pkgs.callPackage ../../packages/codex-computer-use-mcp.nix {};
  cxporterPackage = pkgs.callPackage ../../packages/cxporter.nix {};
  codexConnectorsSkill = pkgs.writeTextDir "share/agents/skills/codex-connectors/SKILL.md" (
    builtins.readFile ./skills/codex-connectors/SKILL.md
  );
  skyComputerUseSkill = pkgs.runCommand "chatgpt-sky-computer-use-skill" {} ''
    skill_dir="$out/share/agents/skills/chatgpt-sky-computer-use"
    mkdir -p "$skill_dir"
    cp ${./skills/chatgpt-sky-computer-use/SKILL.md} "$skill_dir/SKILL.md"
    cp ${./skills/chatgpt-sky-computer-use/REFERENCE.md} "$skill_dir/REFERENCE.md"
  '';
  skyComputerUseExtension =
    pkgs.runCommand "chatgpt-sky-computer-use-extension" {
      nativeBuildInputs = [pkgs.patch];
    } ''
      extension_dir="$out/integrations/pi"
      mkdir -p "$extension_dir"
      cp ${computerUsePackage}/lib/node_modules/codex-computer-use-mcp/integrations/pi/index.ts "$extension_dir/index.ts"
      ln -s ${computerUsePackage}/lib/node_modules/codex-computer-use-mcp/dist "$out/dist"
      patch "$extension_dir/index.ts" < ${./sky-computer-use.patch}
    '';
  computerUseMcpReconcile = pkgs.writeShellApplication {
    name = "omp-reconcile-computer-use-mcp";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      set -euo pipefail

      config_dir="$HOME/.omp/agent"
      config_file="$config_dir/mcp.json"
      mkdir -p "$config_dir"

      input="$config_file"
      seed=""
      if [[ ! -f "$input" ]]; then
        seed="$(mktemp "$config_dir/.mcp.seed.XXXXXX")"
        printf '{}\n' >"$seed"
        input="$seed"
      fi

      updated="$(mktemp "$config_dir/.mcp.json.XXXXXX")"
      cleanup() {
        rm -f "$seed" "$updated"
      }
      trap cleanup EXIT

      jq '
        .["$schema"] //= "https://raw.githubusercontent.com/can1357/oh-my-pi/main/packages/coding-agent/src/config/mcp-schema.json"
        | del(.mcpServers["chatgpt-computer-use"])
        | .disabledServers = (
            (.disabledServers // [])
            | if index("computer-use") == null
              then . + ["computer-use"]
              else .
              end
          )
      ' "$input" >"$updated"

      if [[ -f "$config_file" ]] && cmp -s "$config_file" "$updated"; then
        exit 0
      fi

      mv "$updated" "$config_file"
      trap - EXIT
      rm -f "$seed"
    '';
  };

  collabRelayPackage = pkgs.callPackage ../../packages/omp-collab-relay {};
  yamlFormat = pkgs.formats.yaml {};
  collabHome = "/Users/${cfg.user}";
  collabLogDirectory = "${collabHome}/Library/Logs/omp-collab";
  collabOrigin = "https://${cfg.collab.hostname}";
  collabHostUrl = "ws://127.0.0.1:${toString cfg.collab.port}";
  collabOriginArgs =
    lib.concatMapStringsSep " "
    (origin: "--allowed-origin ${lib.escapeShellArg origin}")
    cfg.collab.allowedOrigins;
  scheduleStartHour = lib.toIntBase10 (builtins.elemAt (lib.splitString ":" cfg.collab.schedule.start) 0);
  scheduleStartMinute = lib.toIntBase10 (builtins.elemAt (lib.splitString ":" cfg.collab.schedule.start) 1);
  scheduleStopHour = lib.toIntBase10 (builtins.elemAt (lib.splitString ":" cfg.collab.schedule.stop) 0);
  scheduleStopMinute = lib.toIntBase10 (builtins.elemAt (lib.splitString ":" cfg.collab.schedule.stop) 1);
  scheduleStartIntervals =
    map (weekday: {
      Weekday = weekday;
      Hour = scheduleStartHour;
      Minute = scheduleStartMinute;
    })
    cfg.collab.schedule.weekdays;
  scheduleStopIntervals =
    map (weekday: {
      Weekday = weekday;
      Hour = scheduleStopHour;
      Minute = scheduleStopMinute;
    })
    cfg.collab.schedule.weekdays;
  scheduleWeekdays = lib.concatStringsSep " " (map toString cfg.collab.schedule.weekdays);
  collabTunnelConfig = yamlFormat.generate "omp-collab-cloudflared.yml" {
    tunnel = cfg.collab.tunnelId;
    "credentials-file" = cfg.collab.credentialsFile;
    ingress = [
      {
        hostname = cfg.collab.hostname;
        service = "http://127.0.0.1:${toString cfg.collab.port}";
        originRequest.access = {
          required = true;
          teamName = cfg.collab.accessTeamName;
          audTag = [cfg.collab.accessAudience];
        };
      }
      {service = "http_status:404";}
    ];
  };

  collabRunner = pkgs.writeShellApplication {
    name = "omp-collab-runner";
    text = ''
      set -euo pipefail

      mkdir -p ${lib.escapeShellArg collabLogDirectory}
      exec >>${lib.escapeShellArg "${collabLogDirectory}/runner.out.log"} \
        2>>${lib.escapeShellArg "${collabLogDirectory}/runner.err.log"}

      relay_pid=""
      tunnel_pid=""
      # shellcheck disable=SC2329
      cleanup() {
        if [[ -n "$tunnel_pid" ]]; then
          /bin/kill -TERM "$tunnel_pid" 2>/dev/null || true
        fi
        if [[ -n "$relay_pid" ]]; then
          /bin/kill -TERM "$relay_pid" 2>/dev/null || true
        fi
        if [[ -n "$tunnel_pid" ]]; then
          wait "$tunnel_pid" 2>/dev/null || true
        fi
        if [[ -n "$relay_pid" ]]; then
          wait "$relay_pid" 2>/dev/null || true
        fi
      }
      trap cleanup EXIT
      trap 'exit 0' INT TERM HUP

      ${lib.getExe cfg.collab.package} \
        --bind 127.0.0.1 \
        --port ${toString cfg.collab.port} \
        --max-guests-per-room ${toString cfg.collab.maxGuestsPerRoom} \
        --max-sockets ${toString cfg.collab.maxSockets} \
        --max-frame-bytes ${toString cfg.collab.maxFrameBytes} \
        --idle-timeout-secs ${toString cfg.collab.idleTimeoutSeconds} \
        --max-connection-secs ${toString cfg.collab.maxConnectionSeconds} \
        --herdr-socket-path ${lib.escapeShellArg cfg.collab.herdrSocketPath} \
        --vault-root ${lib.escapeShellArg cfg.collab.vaultRoot} \
        --public-origin ${lib.escapeShellArg cfg.collab.webUrl} \
        --activation-timeout-secs ${toString cfg.collab.activationTimeoutSeconds} \
        --reconnect-delay-ms ${toString cfg.collab.reconnectDelayMilliseconds} \
        --schedule-weekdays ${lib.escapeShellArg (lib.concatStringsSep "," (map toString cfg.collab.schedule.weekdays))} \
        --schedule-start ${lib.escapeShellArg cfg.collab.schedule.start} \
        --schedule-stop ${lib.escapeShellArg cfg.collab.schedule.stop} \
        --manual-override-secs ${toString cfg.collab.schedule.manualOverrideSeconds} \
        --require-access-jwt \
        ${collabOriginArgs} &
      relay_pid=$!
      attempts=0
      until [[ "$(${lib.getExe pkgs.curl} --fail --silent --max-time 2 \
        "http://127.0.0.1:${toString cfg.collab.port}/healthz" 2>/dev/null || true)" == "omp-collab-relay" ]]; do
        if ! /bin/kill -0 "$relay_pid" 2>/dev/null; then
          wait "$relay_pid"
          exit $?
        fi
        attempts=$((attempts + 1))
        if [[ "$attempts" -ge 30 ]]; then
          echo "OMP collab relay did not become ready" >&2
          exit 1
        fi
        /bin/sleep 1
      done

      ${lib.getExe pkgs.cloudflared} tunnel \
        --no-autoupdate \
        --loglevel info \
        --metrics 127.0.0.1:${toString cfg.collab.metricsPort} \
        --logfile ${lib.escapeShellArg "${collabLogDirectory}/tunnel.log"} \
        --config ${lib.escapeShellArg collabTunnelConfig} \
        run ${lib.escapeShellArg cfg.collab.tunnelId} &
      tunnel_pid=$!

      set +e
      wait -n "$relay_pid" "$tunnel_pid"
      status=$?
      set -e
      exit "$status"
    '';
  };

  collabStart = pkgs.writeShellApplication {
    name = "omp-collab-start";
    runtimeInputs = [pkgs.curl];
    text = ''
      set -euo pipefail

      credentials=${lib.escapeShellArg cfg.collab.credentialsFile}
      if [[ ! -r "$credentials" ]]; then
        echo "OMP collab tunnel credentials are not readable: $credentials" >&2
        exit 1
      fi

      local_health() {
        [[ "$(curl --fail --silent --max-time 2 \
          "http://127.0.0.1:${toString cfg.collab.port}/healthz" 2>/dev/null || true)" == "omp-collab-relay" ]]
      }
      tunnel_health() {
        curl --fail --silent --max-time 2 \
          "http://127.0.0.1:${toString cfg.collab.metricsPort}/ready" >/dev/null 2>&1
      }
      in_schedule() {
        local weekday weekdays now
        weekday="$(/bin/date +%u)"
        weekdays=" ${scheduleWeekdays} "
        now="$(/bin/date +%H:%M)"
        case "$weekdays" in
          *" $weekday "*) [[ ! "$now" < ${lib.escapeShellArg cfg.collab.schedule.start} ]] && [[ "$now" < ${lib.escapeShellArg cfg.collab.schedule.stop} ]] ;;
          *) return 1 ;;
        esac
      }
      request_override() {
        curl --fail --silent --show-error --max-time 2 \
          -X POST "http://127.0.0.1:${toString cfg.collab.port}/api/service/override" >/dev/null
      }

      if local_health && tunnel_health; then
        if ! in_schedule; then request_override; fi
        echo "OMP_COLLAB_STARTED=0"
        echo "OMP collab already available at ${collabOrigin}"
        exit 0
      fi

      domain="gui/$(/usr/bin/id -u)"
      /bin/launchctl kickstart -k "$domain/org.nixos.omp-collab"

      attempts=0
      until local_health; do
        attempts=$((attempts + 1))
        if [[ "$attempts" -ge 30 ]]; then
          echo "OMP collab relay did not become ready" >&2
          exit 1
        fi
        /bin/sleep 1
      done

      attempts=0
      until tunnel_health; do
        attempts=$((attempts + 1))
        if [[ "$attempts" -ge 60 ]]; then
          /bin/launchctl kill SIGTERM "$domain/org.nixos.omp-collab" 2>/dev/null || true
          echo "OMP collab tunnel did not connect to Cloudflare" >&2
          exit 1
        fi
        /bin/sleep 1
      done
      if ! in_schedule; then request_override; fi

      echo "OMP_COLLAB_STARTED=1"
      echo "OMP collab started at ${collabOrigin}"
    '';
  };

  collabStop = pkgs.writeShellApplication {
    name = "omp-collab-stop";
    runtimeInputs = [pkgs.curl];
    text = ''
      set -euo pipefail

      local_health() {
        [[ "$(curl --fail --silent --max-time 2 \
          "http://127.0.0.1:${toString cfg.collab.port}/healthz" 2>/dev/null || true)" == "omp-collab-relay" ]]
      }

      if ! local_health; then
        echo "OMP collab already stopped"
        exit 0
      fi

      curl --fail --silent --show-error --max-time 2 \
        -X POST "http://127.0.0.1:${toString cfg.collab.port}/api/service/stop" >/dev/null

      attempts=0
      while local_health; do
        attempts=$((attempts + 1))
        if [[ "$attempts" -ge 120 ]]; then
          echo "OMP collab relay did not stop after soft shutdown" >&2
          exit 1
        fi
        /bin/sleep 1
      done
      echo "OMP collab stopped"
    '';
  };

  collabStatus = pkgs.writeShellApplication {
    name = "omp-collab-status";
    runtimeInputs = [pkgs.curl];
    text = ''
      set -euo pipefail

      local_body="$(curl --fail --silent --max-time 2 \
        "http://127.0.0.1:${toString cfg.collab.port}/healthz" 2>/dev/null || true)"
      tunnel_ready=0
      if curl --fail --silent --max-time 2 \
        "http://127.0.0.1:${toString cfg.collab.metricsPort}/ready" >/dev/null 2>&1; then
        tunnel_ready=1
      fi

      if [[ "$local_body" == "omp-collab-relay" ]]; then
        echo "Relay: running on 127.0.0.1:${toString cfg.collab.port}"
      else
        echo "Relay: stopped"
      fi
      if [[ "$tunnel_ready" -eq 1 ]]; then
        echo "Tunnel: connected to Cloudflare"
      else
        echo "Tunnel: unavailable"
      fi
    '';
  };
  collabScheduleStart = pkgs.writeShellApplication {
    name = "omp-collab-schedule-start";
    text = ''
      set -euo pipefail
      exec ${lib.getExe collabStart}
    '';
  };

  collabScheduleStop = pkgs.writeShellApplication {
    name = "omp-collab-schedule-stop";
    text = ''
      set -euo pipefail
      exec ${lib.getExe collabStop}
    '';
  };

  collabExtension = mkRemoteCollabExtension {
    startCommand = lib.getExe collabStart;
    stopCommand = lib.getExe collabStop;
    statusCommand = lib.getExe collabStatus;
  };

  wrappedPackage =
    pkgs.runCommand "omp-${cfg.package.version}-with-runtimes" {
      nativeBuildInputs = [pkgs.makeWrapper];
    } ''
      mkdir -p "$out/bin"

      mkdir -p "$out/share"
      cp -R ${cfg.package}/share/. "$out/share/"
      mkdir -p "$out/share/omp"
      cp -R ${assetSrc}/docs "$out/share/omp/docs"
      cp -R ${assetSrc}/packages/coding-agent/examples "$out/share/omp/examples"
      cp ${assetSrc}/packages/coding-agent/CHANGELOG.md "$out/share/omp/CHANGELOG.md"
      cp ${assetSrc}/packages/coding-agent/README.md "$out/share/omp/README.md"

      makeWrapper ${lib.getExe cfg.package} "$out/bin/omp" \
        --prefix PATH : ${lib.escapeShellArg runtimePath} \
        --set-default PI_PY 1 \
        --set-default PI_JS 1 \
        --set-default PI_PACKAGE_DIR "$out/share/omp"
    '';
  spinoffExtension = mkSpinoffExtension {
    ompCommand = "${wrappedPackage}/bin/omp";
    herdrCommand = lib.getExe config.local.herdr.package;
    vaultRoot = "/Users/${cfg.user}/vault";
  };
  managedSettingsSuffix =
    lib.optionalString (cfg.authBrokerUrl != null)
    "\nauth:\n  broker:\n    url: ${builtins.toJSON cfg.authBrokerUrl}\n"
    + lib.optionalString cfg.collab.enable (
      "\ncollab:\n  relayUrl: ${builtins.toJSON collabHostUrl}\n  webUrl: ${builtins.toJSON cfg.collab.webUrl}\n"
      + lib.optionalString (cfg.collab.displayName != null)
      "  displayName: ${builtins.toJSON cfg.collab.displayName}\n"
    );
  managedSettingsFile =
    if managedSettingsSuffix == ""
    then cfg.settingsFile
    else
      pkgs.writeText "omp-config.yml" (
        builtins.readFile cfg.settingsFile
        + managedSettingsSuffix
      );

  mkTheme = {
    name,
    background,
    text,
    accent,
    secondary,
    success,
    error,
    warning,
    muted,
    dim,
    selectedBg,
    statusLineBg,
  }: {
    inherit name;
    colors = {
      accent = accent;
      border = muted;
      borderAccent = secondary;
      borderMuted = dim;
      success = success;
      error = error;
      warning = warning;
      muted = muted;
      dim = dim;
      text = text;
      thinkingText = muted;

      selectedBg = selectedBg;
      userMessageBg = selectedBg;
      customMessageBg = selectedBg;
      toolPendingBg = selectedBg;
      toolSuccessBg = statusLineBg;
      toolErrorBg = selectedBg;
      statusLineBg = statusLineBg;

      userMessageText = text;
      customMessageText = text;
      customMessageLabel = secondary;
      toolTitle = text;
      toolOutput = text;

      mdHeading = accent;
      mdLink = accent;
      mdLinkUrl = secondary;
      mdCode = warning;
      mdCodeBlock = text;
      mdCodeBlockBorder = muted;
      mdQuote = muted;
      mdQuoteBorder = dim;
      mdHr = dim;
      mdListBullet = secondary;

      toolDiffAdded = success;
      toolDiffRemoved = error;
      toolDiffContext = muted;
      syntaxComment = muted;
      syntaxKeyword = secondary;
      syntaxFunction = accent;
      syntaxVariable = text;
      syntaxString = success;
      syntaxNumber = warning;
      syntaxType = accent;
      syntaxOperator = secondary;
      syntaxPunctuation = dim;

      thinkingOff = dim;
      thinkingMinimal = muted;
      thinkingLow = accent;
      thinkingMedium = success;
      thinkingHigh = warning;
      thinkingXhigh = error;
      bashMode = warning;
      pythonMode = accent;

      statusLineSep = dim;
      statusLineModel = accent;
      statusLinePath = text;
      statusLineGitClean = success;
      statusLineGitDirty = warning;
      statusLineContext = secondary;
      statusLineSpend = warning;
      statusLineStaged = accent;
      statusLineDirty = warning;
      statusLineUntracked = error;
      statusLineOutput = secondary;
      statusLineCost = error;
      statusLineSubagents = success;
    };
    export = {
      pageBg = background;
      cardBg = selectedBg;
      infoBg = statusLineBg;
    };
    symbols.preset = "unicode";
  };

  kanagawaWaveTheme = mkTheme {
    name = "kanagawa-wave";
    background = "#1f1f28";
    text = "#dcd7ba";
    accent = "#7e9cd8";
    secondary = "#957fb8";
    success = "#98bb6c";
    error = "#c34043";
    warning = "#e6c384";
    muted = "#727169";
    dim = "#54546d";
    selectedBg = "#2a2a37";
    statusLineBg = "#090618";
  };

  everforestLightHardTheme = mkTheme {
    name = "everforest-light-hard";
    background = "#f2efdf";
    text = "#5c6a72";
    accent = "#7fbbb3";
    secondary = "#d699b6";
    success = "#9ab373";
    error = "#e67e80";
    warning = "#ceaf72";
    muted = "#a6b0a0";
    dim = "#b2af9f";
    selectedBg = "#f0f2d4";
    statusLineBg = "#e5dfc5";
  };
in {
  options.local.omp = {
    enable = lib.mkEnableOption "global OMP with Nix-provided eval runtimes";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed OMP package and config.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omp;
      description = "OMP package to wrap and install.";
    };

    pythonPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.python314;
      description = "Python interpreter made available to OMP eval cells.";
    };

    bunPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.bun;
      description = "Bun runtime made available to OMP and its tool subprocesses.";
    };

    uvPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.uv;
      description = "uv package manager made available to OMP and its tool subprocesses.";
    };

    extraRuntimePackages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [];
      description = "Additional packages to prepend to PATH for OMP runtime and tool subprocesses.";
    };

    settingsFile = lib.mkOption {
      type = lib.types.path;
      default = ./config.yml;
      description = "YAML config file linked to ~/.omp/agent/config.yml.";
    };

    authBrokerUrl = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
      example = "http://127.0.0.1:18765";
      description = "Auth broker URL to add to the managed OMP config; non-loopback endpoints must use HTTPS.";
    };

    collab = {
      enable = lib.mkEnableOption "on-demand hardened OMP collab relay";

      package = lib.mkOption {
        type = lib.types.package;
        default = collabRelayPackage;
        description = "Version-locked hardened OMP collab relay package.";
      };

      hostname = lib.mkOption {
        type = lib.types.str;
        default = "omp.midsorbet.me";
        description = "Public hostname for the dedicated Cloudflare Tunnel.";
      };
      displayName = lib.mkOption {
        type = with lib.types; nullOr str;
        default = null;
        example = "mini-me";
        description = "Name shown to OMP collab participants; null uses OMP's OS username fallback.";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 17475;
        description = "Loopback port shared by the relay and Cloudflare Tunnel.";
      };

      metricsPort = lib.mkOption {
        type = lib.types.port;
        default = 17476;
        description = "Loopback port for cloudflared readiness and metrics.";
      };

      webUrl = lib.mkOption {
        type = lib.types.str;
        default = collabOrigin;
        description = "Same-origin browser client used in generated OMP collab links.";
      };
      vaultRoot = lib.mkOption {
        type = lib.types.path;
        default = "/Users/${cfg.user}/vault";
        description = "Vault root passed to the remote dashboard's Herdr integration.";
      };
      herdrSocketPath = lib.mkOption {
        type = lib.types.str;
        default = "/Users/${cfg.user}/.config/herdr/herdr.sock";
        description = "Herdr v0.8 local API socket used by the dashboard state subscriber.";
      };

      reconnectDelayMilliseconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 250;
        description = "Delay before reconnecting the Herdr event subscriber.";
      };

      activationTimeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 30;
        description = "Bounded timeout used while activating a Herdr-backed OMP pane.";
      };

      schedule = {
        weekdays = lib.mkOption {
          type = with lib.types; listOf (ints.between 1 7);
          default = [1 2 3 4 5];
          description = "Local weekdays on which the dashboard is available.";
        };

        start = lib.mkOption {
          type = lib.types.strMatching "((0[0-9])|(1[0-9])|(2[0-3])):[0-5][0-9]";
          default = "08:00";
          description = "Local start time for scheduled dashboard availability.";
        };

        stop = lib.mkOption {
          type = lib.types.strMatching "((0[0-9])|(1[0-9])|(2[0-3])):[0-5][0-9]";
          default = "18:00";
          description = "Local stop time for scheduled dashboard availability.";
        };

        manualOverrideSeconds = lib.mkOption {
          type = lib.types.ints.positive;
          default = 7200;
          description = "Out-of-hours manual availability override duration.";
        };
      };

      allowedOrigins = lib.mkOption {
        type = with lib.types; listOf str;
        default = [collabOrigin];
        description = "Browser origins allowed to open relay WebSockets; defaults to the self-hosted client origin.";
      };

      maxGuestsPerRoom = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1;
        description = "Maximum simultaneous guests in each room.";
      };

      maxSockets = lib.mkOption {
        type = lib.types.ints.positive;
        default = 32;
        description = "Maximum total relay WebSocket connections across all rooms.";
      };

      maxFrameBytes = lib.mkOption {
        type = lib.types.ints.positive;
        default = 16 * 1024 * 1024;
        description = "Maximum encrypted WebSocket frame size.";
      };

      idleTimeoutSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1800;
        description = "Inactivity window before an idle room is closed.";
      };

      maxConnectionSeconds = lib.mkOption {
        type = lib.types.ints.positive;
        default = 1800;
        description = "Hard maximum WebSocket lifetime, capped further by the Access JWT expiry.";
      };

      accessTeamName = lib.mkOption {
        type = lib.types.str;
        default = "midsorbet";
        description = "Cloudflare Access team name used for connector-side JWT validation.";
      };

      accessAudience = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Cloudflare Access application audience tag validated by cloudflared.";
      };

      tunnelId = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Dedicated Cloudflare Tunnel UUID.";
      };

      credentialsFile = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Path to the agenix-managed per-tunnel credentials JSON.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions =
      [
        {
          assertion = authBrokerUrlIsSecure;
          message = "local.omp.authBrokerUrl must use HTTPS unless it targets loopback over HTTP.";
        }
      ]
      ++ lib.optionals cfg.collab.enable [
        {
          assertion = pkgs.stdenv.isDarwin;
          message = "local.omp.collab is only supported on Darwin.";
        }
        {
          assertion = cfg.collab.tunnelId != "";
          message = "local.omp.collab.tunnelId must be set.";
        }
        {
          assertion = cfg.collab.credentialsFile != "";
          message = "local.omp.collab.credentialsFile must be set.";
        }
        {
          assertion = cfg.collab.accessAudience != "";
          message = "local.omp.collab.accessAudience must be set.";
        }
        {
          assertion = cfg.collab.metricsPort != cfg.collab.port;
          message = "local.omp.collab.metricsPort must differ from collab.port.";
        }
        {
          assertion = cfg.collab.maxFrameBytes <= 16 * 1024 * 1024;
          message = "local.omp.collab.maxFrameBytes cannot exceed 16 MiB.";
        }
        {
          assertion = cfg.collab.maxSockets >= cfg.collab.maxGuestsPerRoom + 1;
          message = "local.omp.collab.maxSockets must allow one host plus maxGuestsPerRoom.";
        }
        {
          assertion = lib.elem cfg.collab.webUrl cfg.collab.allowedOrigins;
          message = "local.omp.collab.allowedOrigins must include collab.webUrl.";
        }
        {
          assertion = scheduleStartHour < 24 && scheduleStopHour < 24;
          message = "local.omp.collab.schedule start and stop hours must be between 00 and 23.";
        }
        {
          assertion = cfg.collab.schedule.start < cfg.collab.schedule.stop;
          message = "local.omp.collab.schedule.start must be earlier than schedule.stop.";
        }
        {
          assertion = cfg.collab.schedule.weekdays != [];
          message = "local.omp.collab.schedule.weekdays must not be empty.";
        }
      ];

    environment.systemPackages = [
      wrappedPackage
      cxporterPackage
    ];

    hjem.users.${cfg.user} = {
      packages = lib.optionals cfg.collab.enable [
        cfg.collab.package
        collabStart
        collabStop
        collabStatus
      ];

      files = {
        ".omp/agent/config.yml" = {
          source = managedSettingsFile;
          clobber = true;
        };
        ".omp/agent/extensions/spinoff" = {
          type = "symlink";
          source = spinoffExtension;
          clobber = true;
        };
        ".agents/skills/codex-connectors" = {
          type = "symlink";
          source = "${codexConnectorsSkill}/share/agents/skills/codex-connectors";
          clobber = true;
        };
        ".agents/skills/chatgpt-sky-computer-use" = {
          type = "symlink";
          source = "${skyComputerUseSkill}/share/agents/skills/chatgpt-sky-computer-use";
          clobber = true;
        };
        ".omp/agent/extensions/sky-computer-use.ts" = {
          type = "symlink";
          source = "${skyComputerUseExtension}/integrations/pi/index.ts";
          clobber = true;
        };
        ".omp/agent/extensions/remote-collab.ts" = lib.mkIf cfg.collab.enable {
          source = "${collabExtension}/remote-collab.ts";
          clobber = true;
        };
        ".omp/agent/themes/kanagawa-wave.json" = {
          text = builtins.toJSON kanagawaWaveTheme;
          clobber = true;
        };
        ".omp/agent/themes/everforest-light-hard.json" = {
          text = builtins.toJSON everforestLightHardTheme;
          clobber = true;
        };
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo >&2 "Reconciling OMP Computer Use routing..."
      /usr/bin/sudo -u ${lib.escapeShellArg cfg.user} -H ${lib.getExe computerUseMcpReconcile}
    '';

    launchd.user.agents.omp-collab = lib.mkIf cfg.collab.enable {
      command = lib.getExe collabRunner;
      serviceConfig = {
        RunAtLoad = false;
        KeepAlive = false;
        ProcessType = "Background";
      };
    };
    launchd.user.agents.omp-collab-schedule-start = lib.mkIf cfg.collab.enable {
      command = lib.getExe collabScheduleStart;
      serviceConfig = {
        RunAtLoad = false;
        StartCalendarInterval = scheduleStartIntervals;
        ProcessType = "Background";
      };
    };

    launchd.user.agents.omp-collab-schedule-stop = lib.mkIf cfg.collab.enable {
      command = lib.getExe collabScheduleStop;
      serviceConfig = {
        RunAtLoad = false;
        StartCalendarInterval = scheduleStopIntervals;
        ProcessType = "Background";
      };
    };
  };
}
