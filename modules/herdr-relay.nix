{
  config,
  lib,
  pkgs,
  secrets,
  ...
}: let
  cfg = config.local.herdrRelay;
  homeDirectory = "/Users/${cfg.user}";
  hostname = "herdr.midsorbet.me";
  tunnelId = "bd9f42c3-efc9-41c0-92f2-dba61e205ffd";
  relayPackage = pkgs.callPackage ../packages/herdr-relay {};
  tunnelConfig = (pkgs.formats.yaml {}).generate "herdr-cloudflared.yml" {
    tunnel = tunnelId;
    "credentials-file" = config.age.secrets.herdr-remote-tunnel.path;
    ingress = [
      {
        inherit hostname;
        service = "ssh://127.0.0.1:22";
        originRequest.access = {
          required = true;
          teamName = "midsorbet";
          audTag = ["7e6dc85ec1535b7b79e362221ef72fa9e543281ca4141416b3dac4673e2bc623"];
        };
      }
      {service = "http_status:404";}
    ];
  };
  relayConfig = pkgs.writeText "herdr-relay.json" (builtins.toJSON {
    inherit hostname tunnelId tunnelConfig;
    stateDirectory = "${homeDirectory}/Library/Application Support/herdr-relay";
    metricsAddress = "127.0.0.1:17478";
  });
in {
  options.local.herdrRelay = {
    enable = lib.mkEnableOption "on-demand Cloudflare Access SSH relay";
    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "Mini user who controls the relay.";
    };
  };
  config = lib.mkIf cfg.enable {
    age.secrets.herdr-remote-tunnel = {
      file = "${secrets}/herdr-remote-tunnel.age";
      owner = cfg.user;
      group = "staff";
      mode = "400";
    };
    environment.systemPackages = [relayPackage];
    environment.etc."herdr-relay.json".source = relayConfig;
    launchd.user.agents.herdr-relay.serviceConfig = {
      Label = "org.nixos.herdr-relay";
      ProgramArguments = ["${relayPackage}/bin/herdr-relay" "--config" "${relayConfig}" "connect"];
      # launchd resumes only an unexpired lease; cloudflared owns reconnection.
      KeepAlive.SuccessfulExit = false;
      RunAtLoad = true;
      ThrottleInterval = 10;
      ExitTimeOut = 5;
      Umask = 63;
      StandardOutPath = "${homeDirectory}/Library/Logs/herdr-relay.log";
      StandardErrorPath = "${homeDirectory}/Library/Logs/herdr-relay.log";
    };
  };
}
