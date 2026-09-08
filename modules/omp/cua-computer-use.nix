{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.omp;
  computerUseCfg = cfg.computerUse;
  cuaDriverPackage = pkgs.callPackage ../../packages/cua-driver.nix {};
  cuaMcpClientPackage = pkgs.callPackage ../../packages/cua-mcp-client {};
  installedCuaDriver = "/Applications/CuaDriver.app/Contents/MacOS/cua-driver";

  capabilityManifestText = builtins.toJSON {
    version = 3;
    expires_after = "8h";
    idle_timeout = "30m";
    resources.apps =
      map (bundleId: {
        bundle_id = bundleId;
        launch = true;
        windows = "all";
        terminate = "deny";
      })
      computerUseCfg.allowedAppBundleIds;
    allow.tools = builtins.fromJSON (builtins.readFile ./cua-native-tools.json);
  };
  capabilityManifest = pkgs.writeText "cua-driver-capability-manifest.json" capabilityManifestText;

  cuaMcpLauncher = pkgs.writeShellApplication {
    name = "omp-cua-driver-mcp";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      set -euo pipefail

      export CUA_DRIVER_RS_TELEMETRY_ENABLED=false
      export CUA_DRIVER_RS_UPDATE_CHECK=false

      driver=${lib.escapeShellArg installedCuaDriver}
      manifest=${lib.escapeShellArg capabilityManifest}
      expected_manifest_hash="$( { printf 'cua-driver-capability-manifest-v3\0'; cat "$manifest"; } | sha256sum | cut -d ' ' -f 1)"

      print_stop_and_retry_recovery() {
        echo >&2 "Stop the user-owned daemon explicitly with: $driver stop"
        echo >&2 'Then call cua_computer_use again. The managed launcher will not stop or replace an existing daemon automatically.'
      }

      verify_bounded_daemon() {
        local status="$1"
        grep -Fqx '  permission mode: bounded (trusted_startup_configuration)' <<<"$status"
        grep -Fqx '  capability manifest: configured=true, approved_at_startup=true, valid=true' <<<"$status"
        grep -Fqx "  capability manifest sha256: $expected_manifest_hash" <<<"$status"
      }

      if status="$($driver status 2>/dev/null)"; then
        if ! verify_bounded_daemon "$status"; then
          echo >&2 'Cua computer use refused: the running Cua Driver daemon is expired or conflicts with the managed bounded capability manifest.'
          print_stop_and_retry_recovery
          exit 77
        fi
      else
        /usr/bin/open -n -g -a /Applications/CuaDriver.app --args \
          serve \
          --no-permissions-gate \
          --permission-mode bounded \
          --capability-manifest "$manifest" \
          --approve-capability-manifest

        status=""
        for _ in $(seq 1 100); do
          if status="$($driver status 2>/dev/null)"; then
            break
          fi
          sleep 0.1
        done
        if [[ -z "$status" ]] || ! verify_bounded_daemon "$status"; then
          echo >&2 'Cua computer use refused: the managed bounded Cua Driver daemon did not become ready with the exact approved capability manifest.'
          print_stop_and_retry_recovery
          exit 77
        fi
      fi

      exec "$driver" mcp
    '';
  };

  cuaExtensionSource = pkgs.replaceVars ./extensions/cua-computer-use.ts {
    CUA_ALLOWED_APP_IDS = builtins.toJSON computerUseCfg.allowedAppBundleIds;
    CUA_MCP_CLIENT = "${cuaMcpClientPackage}/lib/cua-mcp-client.ts";
    CUA_MCP_LAUNCHER = lib.getExe cuaMcpLauncher;
  };
  cuaExtensionTree = pkgs.runCommand "omp-cua-computer-use-extension" {} ''
    mkdir -p "$out/extensions"
    cp ${cuaExtensionSource} "$out/extensions/cua-computer-use.ts"
    cp ${./cua-native-tools.json} "$out/cua-native-tools.json"
  '';

  reconcileCuaConfiguration = pkgs.writeShellApplication {
    name = "omp-reconcile-cua-computer-use";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      set -euo pipefail

      reconcile_json_atomically() (
        local config_file="$1"
        local filter="$2"
        local config_dir
        local input_mode=""
        local updated=""

        trap 'if [[ -n "$updated" ]]; then rm -f -- "$updated"; fi' EXIT

        config_dir="$(dirname "$config_file")"
        mkdir -p "$config_dir"
        if [[ -L "$config_file" ]]; then
          echo >&2 "Cua configuration reconciliation refused: $config_file is a symlink; leaving it unchanged."
          exit 77
        fi
        if [[ -e "$config_file" ]] && [[ ! -f "$config_file" ]]; then
          echo >&2 "Cua configuration reconciliation refused: $config_file is not a regular file; leaving it unchanged."
          exit 77
        fi

        updated="$(mktemp "$config_dir/.cua-reconcile.XXXXXX")"
        if [[ -f "$config_file" ]]; then
          input_mode="$(/usr/bin/stat -f '%Lp' "$config_file")"
          jq "$filter" "$config_file" >"$updated"
          chmod "$input_mode" "$updated"
        else
          printf '{}\n' | jq "$filter" >"$updated"
          chmod 0600 "$updated"
        fi

        if [[ ! -f "$config_file" ]] || ! cmp -s "$config_file" "$updated"; then
          mv -f -- "$updated" "$config_file"
          updated=""
        fi
      )

      reconcile_json_atomically "$HOME/.cua-driver/config.json" '
        if type != "object" then
          error("Cua privacy configuration must be a JSON object")
        else
          .telemetry_enabled = false
          | .update_check_enabled = false
        end
      '

      reconcile_json_atomically "$HOME/.omp/agent/mcp.json" '
        if type != "object" then
          error("OMP MCP configuration must be a JSON object")
        elif has("mcpServers") and (.mcpServers | type) != "object" then
          error("OMP mcpServers must be a JSON object")
        elif has("disabledServers") and (.disabledServers | type) != "array" then
          error("OMP disabledServers must be a JSON array")
        else
          if has("mcpServers") then
            .mcpServers |= del(
              .["chatgpt-computer-use"],
              .["computer-use"],
              .["cua-driver"]
            )
          else
            .
          end
          | if has("disabledServers") then
              .disabledServers |= map(select(
                . != "chatgpt-computer-use"
                and . != "computer-use"
                and . != "cua-driver"
              ))
            else
              .
            end
        end
      '

      remove_managed_sky_symlink() {
        local stale_path="$1"
        local stale_target

        if [[ ! -e "$stale_path" ]] && [[ ! -L "$stale_path" ]]; then
          return
        fi
        if [[ ! -L "$stale_path" ]]; then
          echo >&2 "Cua configuration reconciliation refused: $stale_path is user-owned, not a managed symlink; leaving it unchanged."
          exit 77
        fi

        stale_target="$(readlink "$stale_path")"
        case "$stale_target" in
          /nix/store/*-sky-computer-use-*/*)
            rm -- "$stale_path"
            ;;
          *)
            echo >&2 "Cua configuration reconciliation refused: $stale_path points to $stale_target, not a managed /nix/store/*-sky-computer-use-* target; leaving it unchanged."
            exit 77
            ;;
        esac
      }

      remove_managed_sky_symlink "$HOME/.agents/skills/chatgpt-sky-computer-use"
      remove_managed_sky_symlink "$HOME/.omp/agent/extensions/sky-computer-use.ts"
    '';
  };

  installSignedCuaApplication = pkgs.writeShellApplication {
    name = "install-signed-cua-driver-application";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = builtins.readFile (pkgs.replaceVars ./cua-install-application.sh {
      CUA_PACKAGE = toString cuaDriverPackage;
      CUA_USER = cfg.user;
    });
  };
in {
  options.local.omp.computerUse.allowedAppBundleIds = lib.mkOption {
    type = with lib.types; listOf (strMatching "[A-Za-z0-9._-]+");
    default = [
      "com.apple.TextEdit"
      "com.apple.calculator"
      "com.cookwell.app"
    ];
    description = "Exact native application bundle identifiers admitted by the Cua capability manifest and OMP launch guard.";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = computerUseCfg.allowedAppBundleIds != [];
        message = "local.omp.computerUse.allowedAppBundleIds must contain at least one explicit application bundle identifier.";
      }
      {
        assertion = lib.length computerUseCfg.allowedAppBundleIds == lib.length (lib.unique computerUseCfg.allowedAppBundleIds);
        message = "local.omp.computerUse.allowedAppBundleIds must not contain duplicates.";
      }
    ];

    hjem.users.${cfg.user}.files = {
      ".agents/skills/cua-computer-use" = {
        type = "symlink";
        source = ./skills/cua-computer-use;
        clobber = true;
      };
      ".omp/agent/extensions/cua-computer-use.ts" = {
        type = "symlink";
        source = "${cuaExtensionTree}/extensions/cua-computer-use.ts";
        clobber = true;
      };
    };

    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo >&2 "Reconciling bounded Cua computer use configuration..."
      /usr/bin/sudo -u ${lib.escapeShellArg cfg.user} -H ${lib.getExe reconcileCuaConfiguration}
      echo >&2 "Installing signed Cua Driver application..."
      ${lib.getExe installSignedCuaApplication}
    '';
  };
}
