{
  config,
  lib,
  pkgs,
  ...
}: let
  photosHostname = "photos.midsorbet.me";
  readeckHostname = "readeck.midsorbet.me";
  actualHostname = "budget.midsorbet.me";
  managedNetworkCaddyfile = pkgs.writeText "home-managed-network.Caddyfile" ''
    {
      admin off
      auto_https off
      log {
        level ERROR
      }
    }
    https://:9443 {
      bind 192.168.4.200
      tls ${./home-managed-network-cert.pem} ${config.age.secrets."home-managed-network-key".path}
      respond 204
    }
  '';
in {
  security.acme = {
    acceptTerms = true;
    defaults = {
      dnsResolver = "1.1.1.1:53";
      enableDebugLogs = false;
    };
    certs.${photosHostname} = {
      dnsProvider = "cloudflare";
      keyType = "ec256";
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.age.secrets."cloudflare-acme-dns-token".path;
    };
    certs.${readeckHostname} = {
      dnsProvider = "cloudflare";
      keyType = "ec256";
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.age.secrets."cloudflare-acme-dns-token".path;
    };
    certs.${actualHostname} = {
      dnsProvider = "cloudflare";
      keyType = "ec256";
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.age.secrets."cloudflare-acme-dns-token".path;
    };
  };
  environment.persistence."/persist".directories = [
    "/var/lib/acme"
    "/var/lib/caddy"
  ];

  services.caddy = {
    enable = true;
    globalConfig = ''
      auto_https disable_redirects
      grace_period 10s
      servers {
        protocols h1 h2
      }
    '';
    virtualHosts.${photosHostname} = {
      useACMEHost = photosHostname;
      listenAddresses = ["192.168.4.200"];
      logFormat = null;
      extraConfig = ''
        reverse_proxy 127.0.0.1:2283 {
          header_up -Cf-Access-Jwt-Assertion
          header_up -Cf-Access-Authenticated-User-Email
          header_up -Cf-Connecting-IP
          header_up -Cf-Ipcountry
          header_up -Cf-Ray
          header_up -Cf-Visitor
        }
      '';
    };
    virtualHosts.${readeckHostname} = {
      useACMEHost = readeckHostname;
      listenAddresses = ["192.168.4.200"];
      logFormat = null;
      extraConfig = ''
        reverse_proxy 127.0.0.1:8000 {
          header_up -Cf-Access-Jwt-Assertion
          header_up -Cf-Access-Authenticated-User-Email
          header_up -Cf-Connecting-IP
          header_up -Cf-Ipcountry
          header_up -Cf-Ray
          header_up -Cf-Visitor
        }
      '';
    };
    virtualHosts.${actualHostname} = {
      useACMEHost = actualHostname;
      listenAddresses = ["192.168.4.200"];
      logFormat = null;
      extraConfig = ''
        reverse_proxy 127.0.0.1:5006 {
          header_up -Cf-Access-Jwt-Assertion
          header_up -Cf-Access-Authenticated-User-Email
          header_up -Cf-Connecting-IP
          header_up -Cf-Ipcountry
          header_up -Cf-Ray
          header_up -Cf-Visitor
        }
      '';
    };
  };

  systemd.services.home-managed-network-beacon = {
    description = "LAN-only Cloudflare Managed Network TLS beacon";
    wantedBy = ["multi-user.target"];
    wants = ["network-online.target"];
    after = ["network-online.target"];
    serviceConfig = {
      ExecStart = "${lib.getExe config.services.caddy.package} run --config ${managedNetworkCaddyfile} --adapter caddyfile";
      User = "caddy";
      Group = "caddy";
      Restart = "on-failure";
      RestartSec = "5s";
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectHome = true;
      ProtectSystem = "strict";
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      RestrictAddressFamilies = ["AF_INET" "AF_UNIX"];
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = true;
    };
  };

  networking.firewall.interfaces.enp1s0.allowedTCPPorts = [443 9443];
}
