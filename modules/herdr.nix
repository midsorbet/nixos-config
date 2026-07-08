{
  config,
  herdr,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.herdr;
  tomlFormat = pkgs.formats.toml {};

  integrationHelper = pkgs.writeShellScriptBin "herdr-install-agent-integrations" ''
    set -euo pipefail

    ${lib.getExe cfg.package} integration install codex
    ${lib.getExe cfg.package} integration install omp
    ${lib.getExe cfg.package} integration status
  '';
in {
  options.local.herdr = {
    enable = lib.mkEnableOption "Herdr terminal agent multiplexer";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed Herdr package and config.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = herdr.packages.${pkgs.stdenv.hostPlatform.system}.herdr;
      description = "Herdr package to install.";
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {
        onboarding = false;

        update = {
          channel = "stable";
          version_check = false;
          manifest_check = true;
        };

        terminal = {
          default_shell = "zsh";
          shell_mode = "auto";
          new_cwd = "follow";
        };

        remote.manage_ssh_config = true;

        keys = {
          prefix = "ctrl+b";
          detach = "prefix+q";
          switch_tab = "prefix+1..9";
          switch_workspace = "prefix+shift+1..9";
          focus_agent = "prefix+alt+1..9";
        };

        theme = {
          name = "kanagawa";
          auto_switch = true;
          light_name = "terminal";
          dark_name = "kanagawa";
        };

        ui = {
          mouse_capture = true;
          toast = {
            delivery = "terminal";
            delay_seconds = 1;
            herdr.position = "bottom-right";
            clipboard = {
              enabled = true;
              position = "bottom-center";
            };
          };
        };

        session.resume_agents_on_restore = true;

        experimental = {
          allow_nested = false;
          pane_history = true;
          kitty_graphics = true;
        };
      };
      description = "Herdr TOML configuration written to the user's XDG config directory.";
    };

    installCodexSkill = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Herdr's agent skill into the user's Codex skills directory.";
    };

    installOmpExtension = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install Herdr's OMP agent-state extension into the user's OMP agent directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user} = {
      packages = [cfg.package integrationHelper];

      xdg.config.files."herdr/config.toml" = lib.mkIf (cfg.settings != {}) {
        source = tomlFormat.generate "herdr-config.toml" cfg.settings;
        clobber = true;
      };

      files = lib.mkMerge [
        (lib.mkIf cfg.installCodexSkill {
          ".codex/skills/herdr/SKILL.md" = {
            source = "${herdr}/SKILL.md";
            clobber = true;
          };
        })

        (lib.mkIf cfg.installOmpExtension {
          ".omp/agent/extensions/herdr-omp-agent-state.ts" = {
            source = "${herdr}/src/integration/assets/omp/herdr-agent-state.ts";
            clobber = true;
          };
        })
      ];
    };
  };
}
