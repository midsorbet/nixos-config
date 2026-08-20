{
  jdtlsWrapper,
  metalsWrapper,
  nixdWrapper,
}: {
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
}
