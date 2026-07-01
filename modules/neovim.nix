{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.neovim;

  # Vendored from nvim-mini/MiniMax configs/nvim-0.12 at rev
  # 35dfab31cf290d74493403853822899af7c8464b, then patched locally.
  minimaxConfig = ./neovim/minimax-config;

  mkFlakeEnvWrapper = {
    name,
    package,
  }:
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.coreutils
        pkgs.nix
      ];
      text = ''
        find_flake_root() {
          dir="$PWD"
          while [ "$dir" != "/" ]; do
            if [ -f "$dir/flake.nix" ]; then
              printf '%s\n' "$dir"
              return 0
            fi
            dir="$(dirname "$dir")"
          done
          return 1
        }

        if flake_root="$(find_flake_root)"; then
          if dev_env="$(nix print-dev-env "$flake_root" 2>/dev/null)"; then
            eval "$dev_env"
          fi
        fi

        exec ${lib.getExe package} "$@"
      '';
    };

  metalsWrapper = mkFlakeEnvWrapper {
    name = "metals";
    package = pkgs.metals;
  };

  jdtlsWrapper = mkFlakeEnvWrapper {
    name = "jdtls";
    package = pkgs.jdt-language-server;
  };
in {
  options.local.neovim = {
    enable = lib.mkEnableOption "Neovim MiniMax configuration";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed MiniMax Neovim config.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user} = {
      packages = [
        metalsWrapper
        jdtlsWrapper
        pkgs.jdk
        pkgs.maven
        pkgs.marksman
        pkgs.vscode-langservers-extracted
      ];

      xdg.config.files."nvim" = {
        type = "symlink";
        source = minimaxConfig;
        clobber = true;
      };
    };
  };
}
