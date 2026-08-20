{
  config,
  lib,
  nix-wrapper-modules,
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

  neovimWrapperModule = {
    config,
    lib,
    pkgs,
    wlib,
    ...
  }: {
    imports = [wlib.wrapperModules.neovim];

    config = {
      settings = {
        config_directory = ./config;
        info_plugin_name = "nix-minimax";
      };

      hosts = {
        python3.nvim-host.enable = false;
        node.nvim-host.enable = false;
        ruby.nvim-host.enable = false;
      };

      specMods = {
        options.runtimePkgs = lib.mkOption {
          type = with lib.types; listOf package;
          default = [];
          description = "Runtime packages added to the wrapped Neovim PATH when this spec is enabled.";
        };
      };

      runtimePkgs = config.specCollect (acc: spec: acc ++ (spec.runtimePkgs or [])) [];

      specs = {
        mini = {
          lazy = false;
          data = [pkgs.vimPlugins.mini-nvim];
        };

        colorschemes = {
          lazy = false;
          data = with pkgs.vimPlugins; [
            everforest
            kanagawa-nvim
          ];
        };

        externalPlugins = {
          lazy = false;
          data = with pkgs.vimPlugins; [
            conform-nvim
            friendly-snippets
            nvim-lspconfig
            nvim-treesitter.withAllGrammars
            nvim-treesitter-textobjects
          ];
          runtimePkgs = [
            jdtlsWrapper
            metalsWrapper
            nixdWrapper
            pkgs.marksman
            pkgs.vscode-langservers-extracted
          ];
        };
      };
    };
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
    environment.variables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
    };

    local.git.settings.core.editor = lib.mkDefault "nvim";

    hjem.users.${cfg.user}.packages = [cfg.package];
  };
}
