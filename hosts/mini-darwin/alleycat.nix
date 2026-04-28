{
  config,
  lib,
  pkgs,
  ...
}: let
  user = config.system.primaryUser;
  home = config.system.primaryUserHome;
  package = pkgs.rustPlatform.buildRustPackage {
    pname = "alleycat";
    version = "0-unstable-2026-04-28";

    src = pkgs.fetchFromGitHub {
      owner = "dnakov";
      repo = "alleycat";
      rev = "dc16fbdcd65367d98ac3a5b790d3d504f47f2c1f";
      hash = "sha256-GdXkDMnIjcHYZebh75kYW1fwE/fQmi/7k3sh4aR3FeU=";
    };

    cargoHash = "sha256-5+Db1rfukuZTfEGFr8DdA1n/19BL3Pb2y7+AZgH+BWQ=";

    cargoBuildFlags = ["-p" "alleycat"];
    cargoTestFlags = ["-p" "alleycat"];

    meta = {
      description = "Small QUIC tunnel for routable hosts";
      homepage = "https://github.com/dnakov/alleycat";
      license = lib.licenses.gpl3Only;
      mainProgram = "alleycat";
    };
  };
  configFile = (pkgs.formats.toml {}).generate "alleycat-config.toml" {
    relay = {
      bind = "0.0.0.0";
      udp_port = 0;
    };
    allowlist = {
      tcp = ["127.0.0.1:8390"];
      unix = [];
    };
    host.overrides = ["100.96.0.4"];
    log.level = "info";
  };
  configDir = "${home}/Library/Application Support/dev.Alleycat.alleycat";
  configPath = "${configDir}/config.toml";
  logDir = "${home}/Library/Logs/dev.Alleycat.alleycat";
in {
  environment.systemPackages = [package];

  launchd.user.agents.alleycat = {
    environment = {
      HOME = home;
    };
    serviceConfig = {
      Label = "dev.alleycat.alleycat";
      ProgramArguments = [
        "${package}/bin/alleycat"
        "run"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${logDir}/launchd.out.log";
      StandardErrorPath = "${logDir}/launchd.err.log";
    };
  };

  system.activationScripts.postActivation.text = lib.mkAfter ''
    echo >&2 "Setting up Alleycat config for ${user}..."
    /usr/bin/install -d -m 700 -o ${lib.escapeShellArg user} ${lib.escapeShellArg configDir} ${lib.escapeShellArg logDir}
    /bin/cp ${lib.escapeShellArg configFile} ${lib.escapeShellArg configPath}
    /usr/sbin/chown ${lib.escapeShellArg user} ${lib.escapeShellArg configPath}
    /bin/chmod 600 ${lib.escapeShellArg configPath}
  '';
}
