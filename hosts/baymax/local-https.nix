{config, ...}: let
  photosHostname = "photos.midsorbet.me";
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
  };

  networking.firewall.interfaces.enp1s0.allowedTCPPorts = [443];
}
