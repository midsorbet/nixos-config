{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.mole;
  homeDirectory = "/Users/${cfg.user}";

  librarianCheckoutCleanup = pkgs.writeShellApplication {
    name = "mole-librarian-checkout-cleanup";

    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.git
    ];

    text = ''
      set -euo pipefail

      export HOME="${homeDirectory}"
      export USER="${cfg.user}"

      log_dir="$HOME/Library/Logs/mole"
      mkdir -p "$log_dir"
      exec >> "$log_dir/librarian-checkout-cleanup.log" 2>&1

      cache_root="''${LIBRARIAN_CACHE_ROOT:-$HOME/.cache/checkouts}"
      now_epoch="$(date +%s)"
      max_age_seconds=$((${toString cfg.librarianCheckoutMaxAgeDays} * 24 * 60 * 60))
      cutoff_epoch=$((now_epoch - max_age_seconds))

      echo "== $(date '+%Y-%m-%d %H:%M:%S') librarian checkout cleanup =="

      if [[ ! -d "$cache_root" ]]; then
        echo "Librarian checkout cache is absent: $cache_root"
        exit 0
      fi

      while IFS= read -r -d "" marker; do
        checkout="''${marker%/.git/librarian-last-fetch}"
        marker_value="$(cat "$marker" 2>/dev/null || true)"

        if [[ ! "$marker_value" =~ ^[0-9]{1,11}$ ]]; then
          echo "Preserving checkout with invalid librarian marker: $checkout"
          continue
        fi

        last_fetch_epoch=$((10#$marker_value))
        if ((last_fetch_epoch > cutoff_epoch)); then
          continue
        fi

        if ! checkout_status="$(git -C "$checkout" status --porcelain=v1 --untracked-files=normal 2>&1)"; then
          echo "Preserving checkout that Git could not inspect: $checkout"
          continue
        fi

        if [[ -n "$checkout_status" ]]; then
          echo "Preserving dirty checkout: $checkout"
          continue
        fi

        if [[ "$(cat "$marker" 2>/dev/null || true)" != "$marker_value" ]]; then
          echo "Preserving checkout used during cleanup: $checkout"
          continue
        fi

        rm -rf -- "$checkout"
        echo "Removed checkout last fetched at epoch $last_fetch_epoch: $checkout"
      done < <(find "$cache_root" -type f -path '*/.git/librarian-last-fetch' -print0)

      echo "== librarian checkout cleanup complete =="
    '';
  };
in {
  options.local.mole = {
    enable = lib.mkEnableOption "Mole macOS system cleaner";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that receives Mole and runs the monthly Librarian checkout cleanup job.";
    };

    librarianCheckoutMaxAgeDays = lib.mkOption {
      type = lib.types.ints.between 1 3650;
      default = 21;
      description = "Minimum last-fetch age in days of a clean Librarian checkout before the monthly job removes it.";
    };

    monthlyInterval = lib.mkOption {
      type = lib.types.attrsOf lib.types.int;
      default = {
        Day = 1;
        Hour = 3;
        Minute = 0;
      };
      description = "Monthly launchd calendar interval for the Librarian checkout cleanup job.";
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

    launchd.user.agents.mole-librarian-checkout-cleanup = {
      command = "${librarianCheckoutCleanup}/bin/mole-librarian-checkout-cleanup";
      serviceConfig = {
        RunAtLoad = false;
        StartCalendarInterval = cfg.monthlyInterval;
      };
    };
  };
}
