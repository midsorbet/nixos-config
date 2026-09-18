{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.omp;
  jsonFormat = pkgs.formats.json {};
  managedServersJson = builtins.toJSON cfg.mcpServers;

  reconcileMcpConfiguration = pkgs.writeShellApplication {
    name = "omp-reconcile-mcp-configuration";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      set -euo pipefail

      config_file="$HOME/.omp/agent/mcp.json"
      config_dir="$(dirname "$config_file")"
      managed_servers=${lib.escapeShellArg managedServersJson}
      updated=""

      cleanup() {
        if [[ -n "$updated" ]]; then
          rm -f -- "$updated"
        fi
      }
      trap cleanup EXIT

      mkdir -p "$config_dir"
      if [[ -L "$config_file" ]]; then
        echo >&2 "OMP MCP configuration reconciliation refused: $config_file is a symlink; leaving it unchanged."
        exit 77
      fi
      if [[ -e "$config_file" ]] && [[ ! -f "$config_file" ]]; then
        echo >&2 "OMP MCP configuration reconciliation refused: $config_file is not a regular file; leaving it unchanged."
        exit 77
      fi

      updated="$(mktemp "$config_dir/.mcp-reconcile.XXXXXX")"
      if [[ -f "$config_file" ]]; then
        input_mode="$(/usr/bin/stat -f '%Lp' "$config_file")"
        jq --argjson managedServers "$managed_servers" '
          if type != "object" then
            error("OMP MCP configuration must be a JSON object")
          elif has("mcpServers") and (.mcpServers | type) != "object" then
            error("OMP mcpServers must be a JSON object")
          elif has("disabledServers") and (.disabledServers | type) != "array" then
            error("OMP disabledServers must be a JSON array")
          else
            .mcpServers = (
              (.mcpServers // {})
              | del(
                  .["chatgpt-computer-use"],
                  .["computer-use"],
                  .["cua-driver"],
                  .hister
                )
              | . + $managedServers
            )
            | if has("disabledServers") then
                .disabledServers |= map(select(
                  . != "chatgpt-computer-use"
                  and . != "computer-use"
                  and . != "cua-driver"
                  and . != "hister"
                ))
              else
                .
              end
          end
        ' "$config_file" >"$updated"
        chmod "$input_mode" "$updated"
      else
        printf '{}\n' | jq --argjson managedServers "$managed_servers" '
          .mcpServers = $managedServers
        ' >"$updated"
        chmod 0600 "$updated"
      fi

      if [[ ! -f "$config_file" ]] || ! cmp -s "$config_file" "$updated"; then
        mv -f -- "$updated" "$config_file"
        updated=""
      fi
    '';
  };
in {
  options.local.omp.mcpServers = lib.mkOption {
    type = lib.types.attrsOf jsonFormat.type;
    default = {};
    internal = true;
    description = "Native MCP server entries managed in the OMP agent configuration.";
  };

  config = lib.mkIf cfg.enable {
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo >&2 "Reconciling native OMP MCP servers..."
      /usr/bin/sudo -u ${lib.escapeShellArg cfg.user} -H ${lib.getExe reconcileMcpConfiguration}
    '';
  };
}
