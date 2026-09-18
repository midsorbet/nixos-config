{
  config,
  lib,
  ...
}: let
  cfg = config.local.workspace;
  homeDir = config.hjem.users.${cfg.user}.directory;
  projectsDir = "${homeDir}/Projects";
  hooksDir = "${homeDir}/.config/git/hooks/projects";
in {
  options.local.workspace = {
    enable = lib.mkEnableOption "independent local project workspace";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User whose project workspace is managed.";
    };
  };

  config = lib.mkIf cfg.enable {
    local.git.settings."includeIf \"gitdir:${projectsDir}/\"" = {
      path = "${homeDir}/.config/git/includes/projects-hooks.gitconfig";
    };

    hjem.users.${cfg.user} = {
      files = {
        "Projects/mani.yaml" = {
          text = lib.replaceStrings ["@PROJECTS_ROOT@"] [projectsDir] (
            builtins.readFile ./mani.yaml
          );
          clobber = true;
        };
        "Projects/AGENTS.md" = {
          text = lib.replaceStrings ["@PROJECTS_ROOT@"] [projectsDir] (
            builtins.readFile ./AGENTS.md
          );
          clobber = true;
        };
      };

      xdg.config.files = {
        "git/hooks/projects/post-commit" = {
          source = ./post-commit.sh;
          clobber = true;
        };
        "git/includes/projects-hooks.gitconfig" = {
          text = ''
            [core]
              hooksPath = ${hooksDir}
          '';
          clobber = true;
        };
      };
    };
  };
}
