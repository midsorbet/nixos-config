vim.loader.enable()

local info_name = vim.g.nix_info_plugin_name or 'nix-minimax'
local ok_info, loaded_info = pcall(require, info_name)
if ok_info then
  _G.nixInfo = loaded_info
else
  package.loaded[info_name] = setmetatable({}, {
    __call = function(_, default) return default end,
  })
  _G.nixInfo = require(info_name)
end

nixInfo.isNix = vim.g.nix_info_plugin_name ~= nil
function nixInfo.get_nix_plugin_path(name)
  return nixInfo(nil, 'plugins', 'lazy', name) or nixInfo(nil, 'plugins', 'start', name)
end

local function safe(label, fn)
  local ok, err = pcall(fn)
  if not ok then
    vim.schedule(function()
      vim.notify(label .. ': ' .. tostring(err), vim.log.levels.ERROR)
    end)
  end
end

local ok_lze, lze = pcall(require, 'lze')
if ok_lze then
  local ok_lzextras, lzextras = pcall(require, 'lzextras')
  nixInfo.lze = ok_lzextras and setmetatable(lze, getmetatable(lzextras)) or lze

  nixInfo.lze.register_handlers({
    {
      spec_field = 'auto_enable',
      set_lazy = false,
      modify = function(plugin)
        if vim.g.nix_info_plugin_name then
          if type(plugin.auto_enable) == 'table' then
            for _, name in pairs(plugin.auto_enable) do
              if not nixInfo.get_nix_plugin_path(name) then
                plugin.enabled = false
                break
              end
            end
          elseif type(plugin.auto_enable) == 'string' then
            plugin.enabled = nixInfo.get_nix_plugin_path(plugin.auto_enable) ~= nil
          elseif type(plugin.auto_enable) == 'boolean' and plugin.auto_enable then
            plugin.enabled = nixInfo.get_nix_plugin_path(plugin.name) ~= nil
          end
        end
        return plugin
      end,
    },
    nixInfo.lze.lsp,
  })

  if nixInfo.lze.h and nixInfo.lze.h.lsp then
    nixInfo.lze.h.lsp.set_ft_fallback(function(name)
      local lspcfg = nixInfo.get_nix_plugin_path('nvim-lspconfig')
      if lspcfg then
        local ok, cfg = pcall(dofile, lspcfg .. '/lsp/' .. name .. '.lua')
        return (ok and cfg or {}).filetypes or {}
      end
      return (vim.lsp.config[name] or {}).filetypes or {}
    end)
  end
end

vim.g.mapleader = ' '
vim.g.maplocalleader = ' '

vim.o.breakindent = true
vim.o.breakindentopt = 'list:-1'
vim.o.colorcolumn = '+1'
vim.o.completeopt = 'menu,preview,noselect'
vim.o.cursorline = true
vim.o.cursorlineopt = 'screenline,number'
vim.o.expandtab = true
vim.o.fillchars = 'eob: ,fold:╌'
vim.o.foldlevel = 99
vim.o.foldmethod = 'expr'
vim.o.foldtext = ''
vim.o.ignorecase = true
vim.o.inccommand = 'split'
vim.o.linebreak = true
vim.o.list = true
vim.o.listchars = 'extends:…,nbsp:␣,precedes:…,tab:> '
vim.o.mouse = 'a'
vim.o.number = true
vim.o.pumborder = 'single'
vim.o.pumheight = 10
vim.o.pummaxwidth = 100
vim.o.relativenumber = true
vim.o.scrolloff = 10
vim.o.shiftround = true
vim.o.shiftwidth = 2
vim.o.signcolumn = 'yes'
vim.o.smartcase = true
vim.o.softtabstop = 2
vim.o.splitbelow = true
vim.o.splitright = true
vim.o.tabstop = 2
vim.o.termguicolors = true
vim.o.timeoutlen = 300
vim.o.undofile = true
vim.o.winborder = 'single'
vim.o.wrap = false

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('no-auto-comment-leader', { clear = true }),
  callback = function()
    vim.cmd('setlocal formatoptions-=c formatoptions-=o')
  end,
  desc = "Don't auto-wrap comments or continue comment leader with o/O",
})

vim.api.nvim_create_autocmd('TextYankPost', {
  group = vim.api.nvim_create_augroup('highlight-yank', { clear = true }),
  callback = function() vim.highlight.on_yank() end,
  desc = 'Highlight yanked text',
})

vim.keymap.set('v', 'J', ":m '>+1<CR>gv=gv", { desc = 'Move line down' })
vim.keymap.set('v', 'K', ":m '<-2<CR>gv=gv", { desc = 'Move line up' })
vim.keymap.set('n', '<C-d>', '<C-d>zz', { desc = 'Scroll down' })
vim.keymap.set('n', '<C-u>', '<C-u>zz', { desc = 'Scroll up' })
vim.keymap.set('n', 'n', 'nzzzv', { desc = 'Next search result' })
vim.keymap.set('n', 'N', 'Nzzzv', { desc = 'Previous search result' })
vim.keymap.set('n', '<leader><leader>[', '<cmd>bprevious<CR>', { desc = 'Previous buffer' })
vim.keymap.set('n', '<leader><leader>]', '<cmd>bnext<CR>', { desc = 'Next buffer' })
vim.keymap.set('n', '<leader><leader>l', '<cmd>b#<CR>', { desc = 'Last buffer' })
vim.keymap.set('n', '<leader><leader>d', '<cmd>bdelete<CR>', { desc = 'Delete buffer' })
vim.keymap.set('n', 'k', "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
vim.keymap.set('n', 'j', "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
vim.keymap.set({ 'v', 'x', 'n' }, '<leader>y', '"+y', { noremap = true, silent = true, desc = 'Yank to clipboard' })
vim.keymap.set({ 'n', 'v', 'x' }, '<leader>Y', '"+yy', { noremap = true, silent = true, desc = 'Yank line to clipboard' })
vim.keymap.set({ 'n', 'v', 'x' }, '<leader>p', '"+p', { noremap = true, silent = true, desc = 'Paste from clipboard' })
vim.keymap.set('i', '<C-p>', '<C-r><C-p>+', { noremap = true, silent = true, desc = 'Paste from clipboard in insert mode' })
vim.keymap.set('x', '<leader>P', '"_dP', { noremap = true, silent = true, desc = 'Paste over selection without replacing clipboard' })
vim.keymap.set('n', '<leader>e', vim.diagnostic.open_float, { desc = 'Open diagnostic message' })
vim.keymap.set('n', '<leader>q', vim.diagnostic.setloclist, { desc = 'Open diagnostics list' })

safe('theme', function()
  vim.g.everforest_background = 'hard'
  vim.g.everforest_better_performance = 1

  local function macos_uses_light()
    if vim.fn.has('mac') ~= 1 then return vim.o.background == 'light' end
    return vim.fn.system({ 'defaults', 'read', '-g', 'AppleInterfaceStyle' }) == ''
  end

  if macos_uses_light() then
    vim.o.background = 'light'
    vim.cmd.colorscheme(nixInfo('everforest', 'settings', 'theme', 'light'))
  else
    vim.o.background = 'dark'
    vim.cmd.colorscheme(nixInfo('kanagawa-wave', 'settings', 'theme', 'dark'))
  end
end)

safe('mini.nvim', function()
  require('mini.basics').setup({ options = { basic = false } })
  require('mini.icons').setup()
  require('mini.notify').setup()
  require('mini.sessions').setup()
  require('mini.starter').setup()
  require('mini.statusline').setup()
  require('mini.tabline').setup()
  require('mini.ai').setup()
  require('mini.align').setup()
  require('mini.bracketed').setup()
  require('mini.comment').setup()
  require('mini.completion').setup()
  require('mini.files').setup()
  require('mini.git').setup()
  require('mini.hipatterns').setup()
  require('mini.jump').setup()
  require('mini.jump2d').setup()
  require('mini.pairs').setup()
  require('mini.pick').setup()
  local snippets = require('mini.snippets')
  local latex_patterns = { 'latex/**/*.json', '**/latex.json' }
  snippets.setup({
    snippets = {
      snippets.gen_loader.from_file(vim.fn.stdpath('config') .. '/snippets/global.json'),
      snippets.gen_loader.from_lang({
        lang_patterns = {
          tex = latex_patterns,
          plaintex = latex_patterns,
          markdown_inline = { 'markdown.json' },
        },
      }),
    },
  })
  require('mini.surround').setup()

  MiniIcons.mock_nvim_web_devicons()
  MiniIcons.tweak_lsp_kind()
end)

local function setup_lsp()
  local function get_jdtls_cache_dir()
    return vim.fn.stdpath('cache') .. '/jdtls'
  end

  local function get_jdtls_workspace_dir()
    return get_jdtls_cache_dir() .. '/workspace'
  end

  local function get_jdtls_jvm_args()
    local env = os.getenv('JDTLS_JVM_ARGS')
    local args = {}
    for a in string.gmatch((env or ''), '%S+') do
      table.insert(args, string.format('--jvm-arg=%s', a))
    end
    return unpack(args)
  end

  vim.lsp.config('html', {
    cmd = { 'vscode-html-language-server', '--stdio' },
  })

  vim.lsp.config('marksman', {
    cmd = { 'marksman', 'server' },
  })

  vim.lsp.config('metals', {
    cmd = { 'metals' },
    filetypes = { 'scala', 'sbt' },
    root_markers = { 'build.sbt', 'build.sc', { 'build.gradle', 'build.gradle.kts' }, 'pom.xml', 'flake.nix', '.git' },
  })

  local root_markers1 = { 'mvnw', 'gradlew', 'settings.gradle', 'settings.gradle.kts', '.git' }
  local root_markers2 = { 'build.xml', 'pom.xml', 'build.gradle', 'build.gradle.kts', 'flake.nix' }
  vim.lsp.config('jdtls', {
    cmd = function(dispatchers, lsp_config)
      local workspace_dir = get_jdtls_workspace_dir()
      local data_dir = workspace_dir
      if lsp_config.root_dir then
        data_dir = data_dir .. '/' .. vim.fn.fnamemodify(lsp_config.root_dir, ':p:h:t')
      end
      local config_cmd = { 'jdtls', '-data', data_dir, get_jdtls_jvm_args() }
      return vim.lsp.rpc.start(config_cmd, dispatchers, {
        cwd = lsp_config.cmd_cwd,
        env = lsp_config.cmd_env,
        detached = lsp_config.detached,
      })
    end,
    filetypes = { 'java' },
    root_markers = vim.fn.has('nvim-0.11.3') == 1 and { root_markers1, root_markers2 }
      or vim.list_extend(root_markers1, root_markers2),
    init_options = {},
  })

  vim.lsp.enable(nixInfo({ 'metals', 'html', 'jdtls', 'marksman' }, 'settings', 'lspServers'))
end

if nixInfo.lze then
  nixInfo.lze.load({
    {
      'nvim-treesitter',
      auto_enable = true,
      event = { 'BufReadPost', 'BufNewFile' },
      after = function()
        vim.api.nvim_create_autocmd('FileType', {
          group = vim.api.nvim_create_augroup('treesitter-start', { clear = true }),
          callback = function(args) pcall(vim.treesitter.start, args.buf) end,
          desc = 'Start tree-sitter for file buffers',
        })
      end,
    },
    {
      'nvim-lspconfig',
      auto_enable = true,
      event = { 'BufReadPre', 'BufNewFile' },
      after = setup_lsp,
    },
    {
      'conform.nvim',
      auto_enable = true,
      event = 'BufWritePre',
      after = function()
        require('conform').setup({
          format_on_save = function(bufnr)
            local disabled = { c = true, cpp = true }
            if disabled[vim.bo[bufnr].filetype] then return nil end
            return { timeout_ms = 500, lsp_format = 'fallback' }
          end,
        })
      end,
    },
    {
      'friendly-snippets',
      auto_enable = true,
      event = 'InsertEnter',
    },
    {
      'gitsigns.nvim',
      auto_enable = true,
      event = { 'BufReadPre', 'BufNewFile' },
      after = function() require('gitsigns').setup() end,
    },
    {
      'which-key.nvim',
      auto_enable = true,
      event = 'VimEnter',
      after = function() require('which-key').setup() end,
    },
    {
      'vim-sleuth',
      auto_enable = true,
      event = { 'BufReadPre', 'BufNewFile' },
    },
  })
end
