{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.hister;
  yamlFormat = pkgs.formats.yaml {};
  histerConfig = yamlFormat.generate "hister-config.yml" {
    app = {
      directory = cfg.dataDir;
      title = "Hister";
      subtitle = "Private search across browsing, Readeck, and the vault";
      search_url = "https://kagi.com/search?q={query}";
      open_results_on_new_tab = true;
      disable_previews = false;
      log_level = "info";
    };
    server = {
      address = cfg.serverAddress;
      base_url = cfg.baseUrl;
      database = "db.sqlite3";
    };
    indexer = {
      detect_languages = true;
      max_file_size_mb = 10;
      directories = [
        {
          path = cfg.vaultMirrorDir;
          label = "vault";
          include_hidden = false;
          delete_on_remove = true;
        }
      ];
    };
    semantic_search = {
      enable = true;
      embedding_endpoint = cfg.embeddingEndpoint;
      embedding_model = "nomic-embed-text";
      dimensions = 768;
      max_context_length = 512;
      chunk_overlap = 50;
      max_embedding_batch_size = 8;
      max_embedding_concurrency = 2;
      query_prefix = "search_query: ";
      document_prefix = "search_document: ";
      similarity_threshold = 0.5;
      result_limit = 10;
      semantic_weight = 0.4;
    };
  };
in {
  options.local.hister = {
    enable = lib.mkEnableOption "private Hister search service";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hister;
      description = "Hister package used by the server and import jobs.";
    };

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/persist/save/hister";
      description = "Backed-up Hister database, previews, and vector index directory.";
    };

    vaultMirrorDir = lib.mkOption {
      type = lib.types.str;
      default = "/persist/save/vault-mirror";
      description = "Receive-only Syncthing vault mirror watched by Hister.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Environment file containing HISTER__APP__ACCESS_TOKEN.";
    };

    readeckEnvironmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Environment file containing HISTER_IMPORT_READECK_TOKEN.";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://hister.midsorbet.me";
      description = "Split-DNS HTTPS URL presented by Caddy.";
    };

    serverAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:4433";
      description = "Loopback address used by the Hister origin server.";
    };

    readeckUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://readeck.midsorbet.me";
      description = "Split-DNS HTTPS Readeck source imported incrementally.";
    };

    embeddingEndpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434/v1/embeddings";
      description = "Mini-hosted Ollama endpoint reached through the reverse SSH forward.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.hister = {};
    users.users.hister = {
      isSystemUser = true;
      group = "hister";
      extraGroups = ["users"];
      home = cfg.dataDir;
    };

    environment.systemPackages = [cfg.package];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0750 hister hister - -"
      "d ${cfg.vaultMirrorDir} 0770 me users - -"
    ];

    systemd.services.hister = {
      description = "Private Hister search service";
      after = ["network-online.target"];
      wants = ["network-online.target"];
      wantedBy = ["multi-user.target"];
      environment.HISTER_CONFIG = histerConfig;
      serviceConfig = {
        ExecStart = "${lib.getExe cfg.package} listen";
        EnvironmentFile = cfg.environmentFile;
        User = "hister";
        Group = "hister";
        WorkingDirectory = cfg.dataDir;
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictAddressFamilies = ["AF_INET" "AF_INET6" "AF_UNIX"];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        ReadWritePaths = [cfg.dataDir];
        ReadOnlyPaths = [cfg.vaultMirrorDir];
        SystemCallArchitectures = "native";
        SystemCallFilter = ["@system-service" "~@privileged"];
      };
      unitConfig.RequiresMountsFor = [cfg.dataDir cfg.vaultMirrorDir];
    };

    systemd.services.hister-readeck-import = {
      description = "Incrementally import Readeck into Hister";
      after = ["hister.service" "network-online.target"];
      wants = ["network-online.target"];
      requires = ["hister.service"];
      environment.HISTER_CONFIG = histerConfig;
      serviceConfig = {
        Type = "oneshot";
        User = "hister";
        Group = "hister";
        EnvironmentFile = [cfg.environmentFile cfg.readeckEnvironmentFile];
        WorkingDirectory = cfg.dataDir;
        ReadWritePaths = [cfg.dataDir];
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe cfg.package)
          "--server-url"
          "http://127.0.0.1:4433"
          "--client-timeout"
          "0"
          "import"
          "readeck"
          cfg.readeckUrl
          "--label"
          "readeck"
          "--batch-size"
          "25"
        ];
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };

    systemd.timers.hister-readeck-import = {
      description = "Hourly Hister Readeck import";
      wantedBy = ["timers.target"];
      timerConfig = {
        OnBootSec = "10m";
        OnUnitActiveSec = "1h";
        RandomizedDelaySec = "5m";
        Persistent = true;
      };
    };
  };
}
