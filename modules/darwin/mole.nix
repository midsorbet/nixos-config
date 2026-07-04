{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.mole;
  homeDirectory = "/Users/${cfg.user}";

  weeklyCleanup = pkgs.writeShellApplication {
    name = "mole-weekly-cleanup";

    text = ''
      set -euo pipefail

      export HOME="${homeDirectory}"
      export USER="${cfg.user}"
      export XDG_CONFIG_HOME="$HOME/.config"

      log_dir="$HOME/Library/Logs/mole"
      mkdir -p "$log_dir" "$XDG_CONFIG_HOME/mole"
      exec >> "$log_dir/weekly-cleanup.log" 2>&1

      echo "== $(date '+%Y-%m-%d %H:%M:%S') mole weekly cleanup =="

      no_privilege_dir="$(mktemp -d "''${TMPDIR:-/tmp}/mole-no-privilege.XXXXXX")"
      cleanup() {
        rm -rf "$no_privilege_dir"
      }
      trap cleanup EXIT INT TERM

      printf '#!/bin/sh\nexit 1\n' > "$no_privilege_dir/sudo"
      chmod 755 "$no_privilege_dir/sudo"

      export PATH="$no_privilege_dir:${lib.makeBinPath [pkgs.bc]}:/opt/homebrew/bin:/usr/local/bin:/run/current-system/sw/bin:/etc/profiles/per-user/${cfg.user}/bin:/usr/bin:/bin:/usr/sbin:/sbin"
      export HOMEBREW_NO_AUTO_UPDATE=1
      export HOMEBREW_NO_ENV_HINTS=1
      export NONINTERACTIVE=1
      export MO_NO_OPLOG=1

      if ! command -v mo >/dev/null 2>&1; then
        echo "mo not found; install should be handled by nix-darwin homebrew.brews"
        exit 0
      fi

      mo --version || true

      echo "-- mo clean --"
      mo clean

      ${lib.optionalString cfg.cleanCacheCheckouts ''
        echo "-- cache checkouts --"
        rm -rf "$HOME/.cache/checkouts"
      ''}

      ${lib.optionalString cfg.runPurge ''
        echo "-- mo purge --"
        mo purge
      ''}

      ${lib.optionalString cfg.runOptimize ''
        echo "-- mo optimize --"
        mo optimize
      ''}

      echo "== mole weekly cleanup complete =="
    '';
  };
in {
  options.local.mole = {
    enable = lib.mkEnableOption "Mole macOS system cleaner";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive Mole configuration and run the weekly cleanup job.";
    };

    runPurge = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the weekly cleanup job should also run `mo purge` for old project build artifacts.";
    };

    runOptimize = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether the weekly cleanup job should also run `mo optimize` after cleanup.";
    };

    cleanCacheCheckouts = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether the weekly cleanup job should remove ~/.cache/checkouts after `mo clean`.";
    };

    purgePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["~/vault/projects"];
      description = "Project roots scanned by `mo purge`; written to ~/.config/mole/purge_paths.";
    };

    interval = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {
        Weekday = 0;
        Hour = 3;
        Minute = 0;
      };
      description = "Weekly launchd calendar interval for the Mole cleanup job; 0 is Sunday.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.isDarwin;
        message = "local.mole is only supported on Darwin.";
      }
    ];

    homebrew.brews = ["mole"];

    hjem.users.${cfg.user}.xdg.config.files."mole/purge_paths" = {
      text = ''
        # Mole Purge Paths - managed by nix-darwin
        # Weekly non-interactive `mo purge` deletes non-recent artifacts under these roots.
        ${lib.concatMapStringsSep "\n" (path: path) cfg.purgePaths}
      '';
      clobber = true;
    };

    launchd.user.agents.mole-weekly-cleanup = {
      command = "${weeklyCleanup}/bin/mole-weekly-cleanup";
      serviceConfig = {
        RunAtLoad = false;
        StartCalendarInterval = cfg.interval;
      };
    };
  };
}
