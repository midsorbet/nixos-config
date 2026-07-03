{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.plannotator;
  sharedAgentSkillNames = [
    "plannotator-annotate"
    "plannotator-last"
    "plannotator-review"
    "plannotator-setup-goal"
    "plannotator-visual-explainer"
  ];
in {
  options.local.plannotator = {
    enable = lib.mkEnableOption "Plannotator plan and code review integration";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed Plannotator package.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.plannotator;
      description = "Plannotator binary package to install.";
    };

    skillsPackage = lib.mkOption {
      type = lib.types.package;
      default = cfg.package.skills;
      description = "Package containing the shared Plannotator agent skills to install into ~/.agents/skills.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user} = {
      packages = [cfg.package];

      files = lib.listToAttrs (map (skillName: {
          name = ".agents/skills/${skillName}";
          value = {
            type = "symlink";
            source = "${cfg.skillsPackage}/share/agents/skills/${skillName}";
            clobber = true;
          };
        })
        sharedAgentSkillNames);
    };
  };
}
