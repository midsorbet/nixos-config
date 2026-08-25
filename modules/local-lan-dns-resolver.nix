{platform}: {
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.lanDnsResolver;

  baymaxLanAddress = "192.168.4.200";
  homeLanNetworks = [
    "192.168.4.0/24"
    "fdef:bd26:b58e:1::/64"
  ];
  gatewayDotHostname = "z9mpdffx5x.cloudflare-gateway.com";
  gatewayDotAddresses = [
    "162.159.36.5"
    "162.159.36.20"
  ];

  localDnsRecords = [
    {
      hostname = "photos.midsorbet.me";
      address = baymaxLanAddress;
    }
    {
      hostname = "readeck.midsorbet.me";
      address = baymaxLanAddress;
    }
    {
      hostname = "budget.midsorbet.me";
      address = baymaxLanAddress;
    }
    {
      hostname = "hister.midsorbet.me";
      address = baymaxLanAddress;
    }
  ];

  gatewayForwardAddresses =
    map (
      address: "${address}@853#${gatewayDotHostname}"
    )
    gatewayDotAddresses;

  sharedUnboundSettings = {
    server = {
      interface = cfg.listenAddresses;
      port = 53;
      access-control =
        (map (network: "${network} allow") homeLanNetworks)
        ++ [
          "0.0.0.0/0 refuse"
          "::0/0 refuse"
        ];
      do-ip4 = true;
      do-ip6 = true;
      do-tcp = true;
      do-udp = true;
      edns-buffer-size = 1232;
      max-udp-size = 1232;
      hide-identity = true;
      hide-version = true;
      minimal-responses = true;
      qname-minimisation = true;
      prefetch = true;
      log-queries = false;
      log-replies = false;
      verbosity = 1;
      tls-cert-bundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
      local-zone = map (record: ''"${record.hostname}." static'') localDnsRecords;
      local-data =
        map (
          record: ''"${record.hostname}. 60 IN A ${record.address}"''
        )
        localDnsRecords;
    };
    forward-zone = [
      {
        name = ''"."'';
        forward-tls-upstream = true;
        forward-addr = gatewayForwardAddresses;
      }
    ];
  };

  renderUnboundOption = indent: name: value:
    if builtins.isBool value
    then "${indent}${name}: ${lib.boolToYesNo value}"
    else if builtins.isInt value
    then "${indent}${name}: ${toString value}"
    else if builtins.isString value
    then "${indent}${name}: ${value}"
    else if builtins.isList value
    then lib.concatMapStringsSep "\n" (renderUnboundOption indent name) value
    else if builtins.isAttrs value
    then
      lib.concatStringsSep "\n" (
        ["${indent}${name}:"]
        ++ lib.mapAttrsToList (renderUnboundOption "${indent}  ") value
      )
    else throw "local.lanDnsResolver: unsupported Unbound setting type";

  renderUnboundSettings = settings:
    lib.concatStringsSep "\n" (lib.mapAttrsToList (renderUnboundOption "") settings) + "\n";

  darwinUnboundSettings = lib.recursiveUpdate sharedUnboundSettings {
    server = {
      chroot = ''""'';
      directory = ''""'';
      do-daemonize = false;
      pidfile = ''""'';
      username = ''"nobody"'';
    };
  };

  darwinUnboundConfigUnchecked = pkgs.writeText "local-lan-unbound.conf" (
    renderUnboundSettings darwinUnboundSettings
  );

  darwinUnboundConfig =
    pkgs.runCommand "local-lan-unbound-checked.conf" {
      nativeBuildInputs = [pkgs.unbound];
      preferLocalBuild = true;
    } ''
      unbound-checkconf ${darwinUnboundConfigUnchecked}
      cp ${darwinUnboundConfigUnchecked} "$out"
    '';
  darwinAddressWaitCommands =
    lib.concatMapStringsSep "\n" (
      address: let
        addressFamily =
          if lib.hasInfix ":" address
          then "inet6"
          else "inet";
      in ''
        while ! /sbin/ifconfig | /usr/bin/grep -q "${addressFamily} ${address} "; do
          /bin/sleep 1
        done
      ''
    )
    cfg.listenAddresses;
  darwinResolverCommand = ''
    while [ ! -x "${pkgs.unbound}/bin/unbound" ] || [ ! -r "${darwinUnboundConfig}" ]; do
      /bin/sleep 1
    done
    ${darwinAddressWaitCommands}
    exec "${pkgs.unbound}/bin/unbound" -d -c "${darwinUnboundConfig}"
  '';
in {
  options.local.lanDnsResolver = {
    enable = lib.mkEnableOption "LAN-only Unbound resolver with Cloudflare Gateway forwarding";

    listenAddresses = lib.mkOption {
      type = lib.types.nonEmptyListOf lib.types.str;
      description = "Static LAN IPv4 and IPv6 addresses where Unbound accepts DNS queries.";
    };
  };

  config = lib.mkIf cfg.enable (
    {
      environment.systemPackages = [pkgs.unbound];
    }
    // (
      if platform == "nixos"
      then {
        services.unbound = {
          enable = true;
          enableRootTrustAnchor = false;
          resolveLocalQueries = false;
          settings = sharedUnboundSettings;
        };
      }
      else if platform == "darwin"
      then {
        launchd.daemons.local-lan-dns-resolver.serviceConfig = {
          ProgramArguments = [
            "/bin/sh"
            "-c"
            darwinResolverCommand
          ];
          RunAtLoad = true;
          KeepAlive = true;
          ProcessType = "Background";
          StandardErrorPath = "/var/log/local-lan-dns-resolver.err.log";
          StandardOutPath = "/var/log/local-lan-dns-resolver.out.log";
          ThrottleInterval = 10;
        };

        system.activationScripts.preActivation.text = lib.mkBefore ''
          currentUnbound="${pkgs.unbound}/bin/unbound"
          while IFS= read -r registeredUnbound; do
            if [[ "$registeredUnbound" != "$currentUnbound" ]]; then
              /usr/libexec/ApplicationFirewall/socketfilterfw --remove "$registeredUnbound"
            fi
          done < <(
            /usr/libexec/ApplicationFirewall/socketfilterfw --listapps \
              | /usr/bin/sed -nE 's|^[[:space:]]*[0-9]+ : (/nix/store/[^[:space:]]+-unbound-[^[:space:]]+/bin/unbound)[[:space:]]*$|\1|p'
          )
          /usr/libexec/ApplicationFirewall/socketfilterfw --add "$currentUnbound"
          /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp "$currentUnbound"
        '';
      }
      else throw "local.lanDnsResolver: unsupported platform ${platform}"
    )
  );
}
