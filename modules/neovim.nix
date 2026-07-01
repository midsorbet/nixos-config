{
  config,
  lib,
  ...
}: let
  cfg = config.local.neovim;

  initLua = ''
    vim.opt.number = true
    vim.opt.relativenumber = true
    vim.opt.hlsearch = true

    vim.keymap.set("n", "<Esc>", "<Cmd>nohlsearch<CR>", {
      desc = "Clear search highlights",
      silent = true,
    })
  '';
in {
  options.local.neovim = {
    enable = lib.mkEnableOption "Neovim configuration";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed Neovim config.";
    };
  };

  config = lib.mkIf cfg.enable {
    hjem.users.${cfg.user}.xdg.config.files."nvim/init.lua" = {
      text = initLua;
      clobber = true;
    };
  };
}
