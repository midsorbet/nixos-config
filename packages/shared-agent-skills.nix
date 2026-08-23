{
  lib,
  pkgs,
  frogPackage,
  skillAgentStuff,
  skillBro,
  skillDiagnosingBugs,
  skillEffectiveHtml,
  skillHumanlayer,
  skillIdeonomy,
  skillModem,
  skillRemindctl,
}: let
  skillNames = [
    "bro"
    "commit"
    "diagnosing-bugs"
    "facts"
    "frog-list"
    "frog-log"
    "frog-resolve"
    "html"
    "html-diagram"
    "html-plan"
    "html-prototype"
    "html-wireframe"
    "ideonomy-plain"
    "librarian"
    "readback"
    "recap"
    "apple-reminders"
    "show-me"
    "uv"
    "write-discoverable-code"
  ];
  frogSkillNames = [
    "frog-list"
    "frog-log"
    "frog-resolve"
  ];
in
  pkgs.runCommand "shared-agent-skills" {
    nativeBuildInputs = [frogPackage];
    passthru = {inherit skillNames;};
  } ''
    set -euo pipefail

    skillRoot="$out/share/agents/skills"
    mkdir -p "$skillRoot"

    cp -R ${skillBro}/skills/bro "$skillRoot/bro"
    # Keep the vault project-hook workflow that is intentionally absent upstream.
    cp -R ${./shared-agent-skills/commit} "$skillRoot/commit"
    cp -R ${skillDiagnosingBugs}/home/.agents/skills/diagnosing-bugs "$skillRoot/diagnosing-bugs"
    cp -R ${skillBro}/skills/facts "$skillRoot/facts"
    cp -R ${skillEffectiveHtml}/skills/html "$skillRoot/html"
    cp -R ${skillEffectiveHtml}/skills/html-diagram "$skillRoot/html-diagram"
    cp -R ${skillEffectiveHtml}/skills/html-plan "$skillRoot/html-plan"
    cp -R ${skillEffectiveHtml}/skills/html-prototype "$skillRoot/html-prototype"
    cp -R ${skillEffectiveHtml}/skills/html-wireframe "$skillRoot/html-wireframe"
    cp -R ${skillIdeonomy}/ideonomy-plain "$skillRoot/ideonomy-plain"
    cp -R ${skillAgentStuff}/skills/librarian "$skillRoot/librarian"
    cp -R ${skillBro}/skills/readback "$skillRoot/readback"
    cp -R ${skillBro}/skills/recap "$skillRoot/recap"
    cp -R ${skillHumanlayer}/plugins/show-me/skills/show-me "$skillRoot/show-me"
    cp -R ${skillAgentStuff}/skills/uv "$skillRoot/uv"
    cp -R ${skillModem}/write-discoverable-code "$skillRoot/write-discoverable-code"
    mkdir -p "$skillRoot/apple-reminders"
    cp ${skillRemindctl}/SKILL.md "$skillRoot/apple-reminders/SKILL.md"

    frogProject="$TMPDIR/frog-project"
    frogHome="$TMPDIR/frog-home"
    mkdir -p "$frogProject" "$frogHome"
    (
      export HOME="$frogHome"
      cd "$frogProject"
      frog skills add --no-global >/dev/null
    )

    for skillName in ${lib.escapeShellArgs frogSkillNames}; do
      cp -R "$frogProject/.agents/skills/$skillName" "$skillRoot/$skillName"
    done

    for skillName in ${lib.escapeShellArgs skillNames}; do
      test -f "$skillRoot/$skillName/SKILL.md"
    done
  ''
