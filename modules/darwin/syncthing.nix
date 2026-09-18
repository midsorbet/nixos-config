{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.syncthing;
  homeDir = config.hjem.users.${cfg.user}.directory;
  projectsHomePrefix = "${homeDir}/";
  projectsRelativePath = lib.removePrefix projectsHomePrefix cfg.projectsPath;
  configDir = "${homeDir}/Library/Application Support/Syncthing";
  canonicalIgnorePolicy = ../workspace/ignore-patterns.txt;
  peerDeviceConfig = pkgs.writeText "syncthing-baymax-device.json" (builtins.toJSON {
    deviceID = cfg.peerDeviceId;
    name = "baymax";
    addresses = [cfg.peerAddress];
    compression = "metadata";
  });
  projectsFolderConfig = pkgs.writeText "syncthing-projects-folder.json" (builtins.toJSON {
    id = "projects";
    label = "Projects";
    path = cfg.projectsPath;
    type = "sendonly";
    devices = [{deviceID = cfg.peerDeviceId;}];
    rescanIntervalS = 3600;
    fsWatcherEnabled = true;
    fsWatcherDelayS = 10;
    ignorePerms = true;
  });
  syncthingStart = pkgs.writeShellApplication {
    name = "syncthing-mini-start";
    runtimeInputs = [cfg.package pkgs.coreutils pkgs.diffutils];
    text = ''
      set -euo pipefail
      install -d -m 700 ${lib.escapeShellArg configDir}
      install -d -m 700 ${lib.escapeShellArg cfg.projectsPath}
      install -m 600 ${lib.escapeShellArg cfg.certFile} ${lib.escapeShellArg "${configDir}/cert.pem"}
      install -m 600 ${lib.escapeShellArg cfg.keyFile} ${lib.escapeShellArg "${configDir}/key.pem"}
      if [[ ! -f ${lib.escapeShellArg "${cfg.projectsPath}/.stignore"} ]]; then
        echo "syncthing-mini-start: refusing to start: Hjem-managed .stignore is missing" >&2
        exit 1
      fi
      if ! cmp -s ${lib.escapeShellArg canonicalIgnorePolicy} ${lib.escapeShellArg "${cfg.projectsPath}/.stignore"}; then
        echo "syncthing-mini-start: refusing to start: Hjem-managed .stignore does not match the canonical policy" >&2
        exit 1
      fi
      exec syncthing serve \
        --no-browser \
        --no-restart \
        --home ${lib.escapeShellArg configDir} \
        --gui-address 127.0.0.1:8384
    '';
  };
  syncthingConfigure = pkgs.writeShellApplication {
    name = "syncthing-mini-configure";
    runtimeInputs = [cfg.package pkgs.coreutils pkgs.gnugrep];
    text = ''
      set -euo pipefail

      cli=(syncthing cli --home ${lib.escapeShellArg configDir})
      ready=false
      for _ in $(seq 1 60); do
        if "''${cli[@]}" config version get >/dev/null 2>&1; then
          ready=true
          break
        fi
        sleep 1
      done
      if [[ "$ready" != true ]]; then
        echo "syncthing-mini-configure: local Syncthing API did not become ready" >&2
        exit 1
      fi

      if ! "''${cli[@]}" config devices list | grep -Fxq ${lib.escapeShellArg cfg.peerDeviceId}; then
        "''${cli[@]}" config devices add-json "$(cat ${lib.escapeShellArg peerDeviceConfig})"
      fi
      "''${cli[@]}" config devices ${lib.escapeShellArg cfg.peerDeviceId} addresses 0 set ${lib.escapeShellArg cfg.peerAddress}
      if "''${cli[@]}" config folders list | grep -Fxq vault; then
        "''${cli[@]}" config folders remove vault
      fi
      if ! "''${cli[@]}" config folders list | grep -Fxq projects; then
        "''${cli[@]}" config folders add-json "$(cat ${lib.escapeShellArg projectsFolderConfig})"
      fi

      "''${cli[@]}" config options global-ann-enabled set false
      "''${cli[@]}" config options local-ann-enabled set false
      "''${cli[@]}" config options relays-enabled set false
      "''${cli[@]}" config options natenabled set false
      "''${cli[@]}" config options start-browser set false
      "''${cli[@]}" config options uraccepted set -- -1
      "''${cli[@]}" config options raw-listen-addresses 0 set tcp://127.0.0.1:0
    '';
  };
in {
  options.local.syncthing = {
    enable = lib.mkEnableOption "send-only Mini Projects Syncthing service";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that owns the Syncthing service and Projects folder.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.syncthing;
      description = "Syncthing package used by the Mini launch agents.";
    };

    certFile = lib.mkOption {
      type = lib.types.path;
      description = "Agenix-decrypted Mini Syncthing certificate.";
    };

    keyFile = lib.mkOption {
      type = lib.types.path;
      description = "Agenix-decrypted Mini Syncthing private key.";
    };

    peerDeviceId = lib.mkOption {
      type = lib.types.str;
      description = "Baymax Syncthing device ID.";
    };

    peerAddress = lib.mkOption {
      type = lib.types.str;
      default = "tcp://127.0.0.1:22000";
      description = "Static LAN address for Baymax Syncthing.";
    };

    projectsPath = lib.mkOption {
      type = lib.types.str;
      default = "${homeDir}/Projects";
      description = "Authoritative Mini Projects directory shared send-only.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasPrefix projectsHomePrefix cfg.projectsPath && projectsRelativePath != "";
        message = "local.syncthing.projectsPath must be a directory beneath the configured Hjem home";
      }
    ];
    hjem.users.${cfg.user} = {
      packages = [cfg.package];
      files."${projectsRelativePath}/.stignore" = {
        type = "copy";
        source = canonicalIgnorePolicy;
        permissions = "0600";
        clobber = true;
      };
    };
    launchd.user.agents.syncthing = {
      serviceConfig = {
        ProgramArguments = ["${syncthingStart}/bin/syncthing-mini-start"];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Background";
        StandardOutPath = "${homeDir}/Library/Logs/syncthing.out.log";
        StandardErrorPath = "${homeDir}/Library/Logs/syncthing.err.log";
        ThrottleInterval = 10;
      };
    };

    launchd.user.agents.syncthing-configure = {
      serviceConfig = {
        ProgramArguments = ["${syncthingConfigure}/bin/syncthing-mini-configure"];
        RunAtLoad = true;
        ProcessType = "Background";
        StandardOutPath = "${homeDir}/Library/Logs/syncthing-configure.out.log";
        StandardErrorPath = "${homeDir}/Library/Logs/syncthing-configure.err.log";
      };
    };
  };
}
