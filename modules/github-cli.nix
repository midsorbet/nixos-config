{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.githubCli;
  yamlFormat = pkgs.formats.yaml {};
in {
  options.local.githubCli = {
    enable = lib.mkEnableOption "Hjem-managed non-secret GitHub CLI defaults";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should own the Hjem-managed GitHub CLI config.";
    };

    settings = lib.mkOption {
      type = yamlFormat.type;
      default = {
        version = 1;
        git_protocol = "ssh";
        prompt = "disabled";
        prefer_editor_prompt = "disabled";
        pager = "hunk pager";
        spinner = "disabled";
        telemetry = "disabled";
      };
      description = ''
        Non-secret GitHub CLI settings written to gh/config.yml.
        Keep tokens out of this value; persistent gh auth belongs in OS
        credential storage, and one-off CLI access can use GH_TOKEN or
        GITHUB_TOKEN in the environment.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user}.xdg.config.files."gh/config.yml" = {
      source = yamlFormat.generate "gh-config.yml" cfg.settings;
      clobber = true;
    };
  };
}
