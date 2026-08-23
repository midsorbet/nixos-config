{
  config,
  lib,
  pkgs,
  skill-agent-stuff,
  skill-bro,
  skill-diagnosing-bugs,
  skill-effective-html,
  skill-humanlayer,
  skill-ideonomy,
  skill-modem,
  skill-remindctl,
  ...
}: let
  cfg = config.local.sharedAgentSkills;
  defaultPackage = pkgs.callPackage ../packages/shared-agent-skills.nix {
    frogPackage = import ../packages/frog {inherit pkgs;};
    skillAgentStuff = skill-agent-stuff;
    skillBro = skill-bro;
    skillDiagnosingBugs = skill-diagnosing-bugs;
    skillEffectiveHtml = skill-effective-html;
    skillHumanlayer = skill-humanlayer;
    skillIdeonomy = skill-ideonomy;
    skillModem = skill-modem;
    skillRemindctl = skill-remindctl;
  };
in {
  options.local.sharedAgentSkills = {
    enable = lib.mkEnableOption "declarative shared agent skills";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed shared agent skills.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "Package containing the selected shared agent skills.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user}.files = lib.listToAttrs (map (skillName: {
        name = ".agents/skills/${skillName}";
        value = {
          type = "symlink";
          source = "${cfg.package}/share/agents/skills/${skillName}";
          clobber = true;
        };
      })
      cfg.package.skillNames);
  };
}
