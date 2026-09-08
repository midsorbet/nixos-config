{platform}: {
  config,
  lib,
  pkgs,
  secrets,
  self,
  ...
}: let
  cfg = config.local.herdrRelay;
  isDarwin = platform == "darwin";
  homeDirectory = "/Users/${cfg.user}";
  stateDirectory =
    if isDarwin
    then "${homeDirectory}/Library/Application Support/herdr-relay"
    else "/var/lib/herdr-relay";
  relayPackage = pkgs.callPackage ../packages/herdr-relay {};
  # Compare the Linux build identity without adding its closure to Mini.
  expectedSystem = builtins.unsafeDiscardStringContext (toString self.nixosConfigurations.hooh.config.system.build.toplevel);
  frpcConfig = (pkgs.formats.toml {}).generate "hooh-frpc.toml" {
    serverAddr = "mini.midsorbet.me";
    serverPort = 7000;
    loginFailExit = false;
    transport.tls = {
      enable = true;
      serverName = "hooh";
      trustedCaFile = "${../hosts/hooh/frp-ca.crt}";
      certFile = "${../hosts/hooh/frp-client.crt}";
      keyFile = config.age.secrets.hooh-frp-client-key.path;
    };
    proxies = [
      {
        name = "mini-ssh";
        type = "tcp";
        localIP = "127.0.0.1";
        localPort = 22;
        remotePort = 2222;
      }
    ];
  };
  relayConfig = pkgs.writeText "herdr-relay.json" (builtins.toJSON ({
      tokenFile = config.age.secrets.herdr-relay-hcloud-token.path;
      inherit stateDirectory expectedSystem;
      hostname = "mini.midsorbet.me";
      imageIdentity = builtins.substring 0 32 (builtins.hashString "sha256" (
        expectedSystem + builtins.readFile ../hosts/hooh/frp-ca.crt + builtins.readFile ../hosts/hooh/hooh-host-key.pub
      ));
    }
    // lib.optionalAttrs isDarwin {
      sshCommand = "/usr/bin/ssh";
      adminKeyFile = "${homeDirectory}/.ssh/id_ed25519";
      hostKeyFile = config.age.secrets.hooh-host-key.path;
      hostPublicKey = lib.trim (builtins.readFile ../hosts/hooh/hooh-host-key.pub);
      miniHostPublicKeyFile = "/etc/ssh/ssh_host_ed25519_key.pub";
      inherit frpcConfig;
    }));
in {
  options.local.herdrRelay = {
    enable = lib.mkEnableOption "Hooh ephemeral frp relay lifecycle";
    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "Mini user who controls the relay.";
    };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      age.secrets.herdr-relay-hcloud-token = {
        file = "${secrets}/herdr-relay-hcloud-token.age";
        mode = "400";
        owner =
          if isDarwin
          then cfg.user
          else "root";
        group =
          if isDarwin
          then "staff"
          else "root";
      };
      environment.systemPackages = [relayPackage];
      environment.etc."herdr-relay.json".source = relayConfig;
    }
    (lib.optionalAttrs isDarwin {
      age.secrets.hooh-frp-client-key = {
        file = "${secrets}/hooh-frp-client-key.age";
        owner = cfg.user;
        group = "staff";
        mode = "400";
      };
      age.secrets.hooh-host-key = {
        file = "${secrets}/hooh-host-key.age";
        owner = cfg.user;
        group = "staff";
        mode = "400";
      };
      launchd.user.agents.herdr-relay.serviceConfig = {
        Label = "org.nixos.herdr-relay";
        ProgramArguments = ["${relayPackage}/bin/herdr-relay" "--config" "${relayConfig}" "connect"];
        KeepAlive.SuccessfulExit = false;
        # launchd retries only unsuccessful exits; valid startup is intentionally successful.
        RunAtLoad = true;
        ThrottleInterval = 10;
        Umask = 63;
        StandardOutPath = "${homeDirectory}/Library/Logs/herdr-relay.log";
        StandardErrorPath = "${homeDirectory}/Library/Logs/herdr-relay.log";
      };
    })
    (lib.optionalAttrs (!isDarwin) {
      systemd.services.herdr-relay-reap = {
        description = "Delete expired Hooh relay servers";
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${relayPackage}/bin/herdr-relay --config ${relayConfig} reap";
          StateDirectory = "herdr-relay";
          StateDirectoryMode = "0700";
          UMask = "0077";
          TimeoutStartSec = "10min";
          NoNewPrivileges = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
          RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        };
      };
      systemd.timers.herdr-relay-reap = {
        description = "Check Hooh cloud leases every minute";
        wantedBy = ["timers.target"];
        timerConfig = {
          OnBootSec = "1min";
          OnUnitActiveSec = "1min";
          AccuracySec = "5s";
        };
      };
    })
  ]);
}
