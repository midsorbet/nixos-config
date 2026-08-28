{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.atuin;
  tomlFormat = pkgs.formats.toml {};

  defaultSettings = {
    sync_address = cfg.syncAddress;
    auto_sync = true;
    sync_frequency = "5m";
    update_check = false;

    search_mode = "fuzzy";
    filter_mode = "global";
    filter_mode_shell_up_key_binding = "session";
    workspaces = true;
    inline_height_shell_up_key_binding = 10;
    enter_accept = false;

    secrets_filter = true;
    history_filter = [
      "(?i)(--password|--token|--secret)(=| +)[^ ]+"
      "(?i)(authorization:|x-api-key:)[[:space:]]*[^[:space:]]+"
    ];
    cwd_filter = [
      "^/Users/me/vault/private(?:/|$)"
      "^/home/me/vault/private(?:/|$)"
    ];

    search.filters = [
      "global"
      "host"
      "session"
      "workspace"
      "directory"
      "session-preload"
    ];
  };

  settings = lib.recursiveUpdate defaultSettings cfg.settings;
in {
  options.local.atuin = {
    enable = lib.mkEnableOption "Hjem-managed Atuin shell history";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed Atuin config.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.atuin;
      description = "Atuin package used by the client and shell integration.";
    };

    syncAddress = lib.mkOption {
      type = lib.types.str;
      default = "https://atuin.midsorbet.me";
      description = "Private split-DNS URL of the self-hosted Atuin sync server.";
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {};
      description = "Additional Atuin settings merged into the managed client config.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    programs.zsh.interactiveShellInit = lib.mkAfter ''
      eval "$(${lib.getExe cfg.package} init zsh --disable-ai)"
    '';

    hjem.users.${cfg.user}.xdg.config.files."atuin/config.toml" = {
      source = tomlFormat.generate "atuin-config.toml" settings;
      clobber = true;
    };
  };
}
