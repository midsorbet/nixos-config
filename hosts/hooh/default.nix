{
  config,
  pkgs,
  lib,
  secrets,
  ...
}: let
  canonicalHostKey = "/etc/ssh/ssh_host_ed25519_key";
  canonicalHostPublicKey = lib.concatStringsSep " " (lib.take 2 (lib.splitString " " (lib.trim (builtins.readFile ./hooh-host-key.pub))));
  leaseCheck = pkgs.writeShellScript "hooh-lease-check" ''
    set -euo pipefail
    trap '${pkgs.systemd}/bin/systemctl --no-block poweroff' ERR
    umask 077
    mkdir -p /run/herdr-relay
    ${pkgs.curl}/bin/curl --fail --silent --show-error --max-time 15 --max-filesize 65536 \
      http://169.254.169.254/hetzner/v1/userdata > /run/herdr-relay/user-data
    IFS= read -r header < /run/herdr-relay/user-data
    test "$header" = '#cloud-config'
    ${pkgs.coreutils}/bin/tail -n +2 /run/herdr-relay/user-data | ${pkgs.jq}/bin/jq -e '
      [.write_files[] | select(.path == "/run/herdr-relay/lease.json")] |
      select(length == 1) | .[0].content | fromjson
    ' > /run/herdr-relay/lease.json
    now="$(${pkgs.coreutils}/bin/date +%s)"
    expires="$(${pkgs.jq}/bin/jq -er --argjson now "$now" '
      .herdr_relay | select(.role == "session" or .role == "image-builder") |
      .expires_at | select(type == "number" and floor == . and . > $now and . <= ($now + 43200))
    ' /run/herdr-relay/lease.json)"
    actual="$(${pkgs.openssh}/bin/ssh-keygen -y -f ${canonicalHostKey} | ${pkgs.coreutils}/bin/cut -d " " -f 1,2)"
    test "$actual" = ${lib.escapeShellArg canonicalHostPublicKey}
    # Replace any previous transient units before arming the same absolute lease expiry.
    for unit in hooh-expiry.timer hooh-expiry.service; do
      ${pkgs.systemd}/bin/systemctl stop "$unit" 2>/dev/null || true
      ${pkgs.systemd}/bin/systemctl reset-failed "$unit" 2>/dev/null || true
    done
    ${pkgs.systemd}/bin/systemd-run --collect --unit=hooh-expiry --on-calendar="@$expires" \
      --property=CollectMode=inactive-or-failed --timer-property=AccuracySec=1s \
      --timer-property=CollectMode=inactive-or-failed ${pkgs.systemd}/bin/systemctl poweroff
  '';
in {
  imports = [./disk-config.nix];
  boot.initrd.availableKernelModules = ["virtio_pci" "virtio_scsi" "virtio_blk" "ahci" "sd_mod"];
  boot.loader.grub.enable = true;
  networking = {
    hostName = "hooh";
    useDHCP = true;
    firewall.allowedTCPPorts = [22 2222 7000];
  };
  time.timeZone = "America/Los_Angeles";
  services.openssh = {
    enable = true;
    generateHostKeys = false;
    hostKeys = [
      {
        path = canonicalHostKey;
        type = "ed25519";
      }
    ];
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      AuthenticationMethods = "publickey";
      AllowUsers = ["me"];
      AllowTcpForwarding = false;
      AllowAgentForwarding = false;
      X11Forwarding = false;
    };
  };
  users.mutableUsers = false;
  users.users.me = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    hashedPassword = "!";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC me@mini-me.local"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
  age.identityPaths = [canonicalHostKey];
  age.secrets.hooh-frp-server-key = {
    file = "${secrets}/hooh-frp-server-key.age";
    mode = "400";
  };
  services.frp.instances.hooh = {
    enable = true;
    role = "server";
    settings = {
      bindAddr = "0.0.0.0";
      bindPort = 7000;
      proxyBindAddr = "0.0.0.0";
      allowPorts = [{single = 2222;}];
      maxPortsPerClient = 1;
      transport.tls = {
        force = true;
        certFile = "${./frp-server.crt}";
        keyFile = "/run/credentials/frp-hooh.service/tls-key";
        trustedCaFile = "${./frp-ca.crt}";
      };
    };
  };
  systemd.services.frp-hooh.serviceConfig.LoadCredential = ["tls-key:${config.age.secrets.hooh-frp-server-key.path}"];
  systemd.services.herdr-relay-lease-check = {
    description = "Validate Hooh lease and arm its native expiry timer";
    wants = ["network-online.target"];
    after = ["network-online.target" "time-sync.target"];
    before = ["sshd.service" "frp-hooh.service"];
    requiredBy = ["sshd.service" "frp-hooh.service"];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = leaseCheck;
    };
  };
  environment.systemPackages = [pkgs.jq];
  system.stateVersion = "26.05";
}
