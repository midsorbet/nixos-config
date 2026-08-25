{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.ollama;
  homeDir = config.hjem.users.${cfg.user}.directory;
  ollamaHost = "127.0.0.1:${toString cfg.port}";
  ollamaModelPull = pkgs.writeShellApplication {
    name = "ollama-ensure-embedding-model";
    runtimeInputs = [cfg.package pkgs.coreutils pkgs.curl];
    text = ''
      set -euo pipefail
      ready=false
      for _ in $(seq 1 120); do
        if curl --fail --silent --show-error http://${ollamaHost}/api/version >/dev/null 2>&1; then
          ready=true
          break
        fi
        sleep 1
      done
      if [[ "$ready" != true ]]; then
        echo "ollama-ensure-embedding-model: Ollama did not become ready" >&2
        exit 1
      fi
      export OLLAMA_HOST=${ollamaHost}
      ollama pull ${lib.escapeShellArg cfg.embeddingModel}
    '';
  };
in {
  options.local.ollama = {
    enable = lib.mkEnableOption "Mini-local Ollama embedding service";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that owns Ollama and its downloaded models.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.ollama;
      description = "Ollama package used by the Mini launch agent.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 11434;
      description = "Loopback Ollama API port forwarded in reverse to Baymax.";
    };

    embeddingModel = lib.mkOption {
      type = lib.types.str;
      default = "nomic-embed-text";
      description = "Embedding model required by Hister semantic search.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user}.packages = [cfg.package];

    launchd.user.agents.ollama = {
      environment = {
        OLLAMA_HOST = ollamaHost;
        OLLAMA_MODELS = "${homeDir}/Library/Application Support/Ollama/models";
      };
      serviceConfig = {
        ProgramArguments = ["${lib.getExe cfg.package}" "serve"];
        RunAtLoad = true;
        KeepAlive = true;
        ProcessType = "Background";
        StandardOutPath = "${homeDir}/Library/Logs/ollama.out.log";
        StandardErrorPath = "${homeDir}/Library/Logs/ollama.err.log";
        ThrottleInterval = 10;
      };
    };

    launchd.user.agents.ollama-embedding-model = {
      environment.OLLAMA_HOST = ollamaHost;
      serviceConfig = {
        ProgramArguments = ["${ollamaModelPull}/bin/ollama-ensure-embedding-model"];
        RunAtLoad = true;
        ProcessType = "Background";
        StandardOutPath = "${homeDir}/Library/Logs/ollama-model.out.log";
        StandardErrorPath = "${homeDir}/Library/Logs/ollama-model.err.log";
      };
    };
  };
}
