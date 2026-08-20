{
  config,
  lib,
  nix-wrapper-modules,
  minimax,
  pkgs,
  ...
}: let
  cfg = config.local.neovim;

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

  nixdWrapper = mkFlakeEnvWrapper {
    name = "nixd";
    package = pkgs.nixd;
  };

  minimaxConfig = pkgs.runCommandLocal "minimax-config" {} ''
    cp -R ${minimax}/configs/nvim-0.12 "$out"
    chmod -R u+w "$out"

    substituteInPlace "$out/init.lua" \
      --replace-fail \
      "vim.pack.add({ 'https://github.com/nvim-mini/mini.nvim' })" \
      "-- Nix supplies mini.nvim in the wrapped runtime."
    substituteInPlace "$out/plugin/40_plugins.lua" \
      --replace-fail \
      "local add = vim.pack.add" \
      "local add = function() end -- Nix supplies external plugins in the wrapped runtime."

    rm "$out/nvim-pack-lock.json" "$out/after/lsp/lua_ls.lua"
    cp ${./neovim/minimax-local.lua} "$out/plugin/90_nix.lua"
  '';

  neovimWrapperModule = import ./neovim/wrapper-module.nix {
    inherit jdtlsWrapper metalsWrapper minimaxConfig nixdWrapper;
  };

  wrappedNeovim = nix-wrapper-modules.lib.evalPackage [
    neovimWrapperModule
    {inherit pkgs;}
  ];
in {
  options.local.neovim = {
    enable = lib.mkEnableOption "Neovim configuration built with nix-wrapper-modules";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed wrapped Neovim package.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = wrappedNeovim;
      description = "Wrapped Neovim package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user}.packages = [cfg.package];
  };
}
