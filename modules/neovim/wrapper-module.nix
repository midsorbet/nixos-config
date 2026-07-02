{
  jdtlsWrapper,
  metalsWrapper,
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
      theme = {
        dark = "kanagawa-wave";
        light = "everforest";
      };
      lspServers = [
        "metals"
        "html"
        "jdtls"
        "marksman"
      ];
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
      lazyLoader = {
        lazy = false;
        data = with pkgs.vimPlugins; [
          lze
          lzextras
        ];
      };

      mini = {
        lazy = false;
        data = with pkgs.vimPlugins; [
          mini-nvim
          mini-icons
        ];
      };

      colorschemes = {
        lazy = false;
        data = with pkgs.vimPlugins; [
          everforest
          kanagawa-nvim
        ];
      };

      general = {
        lazy = true;
        data = with pkgs.vimPlugins; [
          conform-nvim
          friendly-snippets
          gitsigns-nvim
          nvim-lspconfig
          nvim-treesitter.withAllGrammars
          nvim-treesitter-textobjects
          vim-sleuth
          which-key-nvim
        ];
        runtimePkgs = [
          jdtlsWrapper
          metalsWrapper
          pkgs.jdk
          pkgs.maven
          pkgs.marksman
          pkgs.vscode-langservers-extracted
        ];
      };
    };
  };
}
