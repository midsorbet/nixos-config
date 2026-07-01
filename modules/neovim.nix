{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.neovim;

  minimaxSrc = pkgs.fetchFromGitHub {
    owner = "nvim-mini";
    repo = "MiniMax";
    rev = "35dfab31cf290d74493403853822899af7c8464b";
    hash = "sha256-+ebzuEjPE6xp6EU9Pp6E9R4fMCR3uK6dlm/DhSuD/1w=";
  };

  minimaxConfig = pkgs.runCommand "minimax-nvim-config" {} ''
        mkdir -p "$out"
        cp -R "${minimaxSrc}/configs/nvim-0.12/." "$out"/
        chmod -R u+w "$out"

        number_line='vim.o.number         = true       -- Show line numbers'
        number_replacement="$(cat <<'EOF'
    vim.o.number         = true       -- Show line numbers
    vim.o.relativenumber = true       -- Show relative line numbers
    EOF
    )"
        substituteInPlace "$out/plugin/10_options.lua" \
          --replace-fail "$number_line" "$number_replacement"

        keymap_anchor='-- Use this section to add custom general mappings. See `:h vim.keymap.set()`.'
        keymap_replacement="$(cat <<'EOF'
    -- Use this section to add custom general mappings. See `:h vim.keymap.set()`.

    vim.keymap.set('n', '<Esc>', '<Cmd>nohlsearch<CR>', {
      desc = 'Clear search highlights',
      silent = true,
    })
    EOF
    )"
        substituteInPlace "$out/plugin/20_keymaps.lua" \
          --replace-fail "$keymap_anchor" "$keymap_replacement"
  '';
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
    hjem.users.${cfg.user}.xdg.config.files."nvim" = {
      type = "symlink";
      source = minimaxConfig;
      clobber = true;
    };
  };
}
