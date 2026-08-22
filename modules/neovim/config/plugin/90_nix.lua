-- Nix-managed MiniMax customizations: keymaps, appearance, and language servers.

Config.now(function()
  table.insert(Config.leader_group_clues, { mode = 'n', keys = '<Leader>y', desc = '+Yank' })
  table.insert(Config.leader_group_clues, { mode = 'x', keys = '<Leader>y', desc = '+Yank' })

  -- y is for 'Yank'. Common usage:
  -- - `<Leader>yp` - copy the absolute path of the current file
  -- - `<Leader>yr` - copy the current file and line reference
  local copy_current_file_path = function()
    vim.fn.setreg('+', vim.fn.expand('%:p'))
    vim.notify('Copied absolute file path')
  end
  local copy_current_file_reference = function()
    local file_reference = vim.fn.expand('%:p') .. ':' .. vim.fn.line('.')
    vim.fn.setreg('+', file_reference)
    vim.notify('Copied file and line reference')
  end
  local copy_selected_file_reference = function()
    local start_line, end_line = vim.fn.line('v'), vim.fn.line('.')
    if start_line > end_line then start_line, end_line = end_line, start_line end

    local file_reference = vim.fn.expand('%:p') .. ':' .. start_line .. '-' .. end_line
    vim.fn.setreg('+', file_reference)
    vim.notify('Copied file and line range reference')
  end

  vim.keymap.set('n', '<Leader>yp', copy_current_file_path, { desc = 'Absolute path' })
  vim.keymap.set('n', '<Leader>yr', copy_current_file_reference, { desc = 'File reference' })
  vim.keymap.set('x', '<Leader>yr', copy_selected_file_reference, { desc = 'File range reference' })
end)

Config.now(function()
  vim.o.number = true
  vim.o.relativenumber = true
end)

Config.now(function()
  vim.g.everforest_background = 'hard'

  local function macos_uses_light_appearance()
    if vim.fn.has('mac') ~= 1 then return vim.o.background == 'light' end
    vim.fn.system({ '/usr/bin/defaults', 'read', '-g', 'AppleInterfaceStyle' })
    return vim.v.shell_error ~= 0
  end

  if macos_uses_light_appearance() then
    vim.o.background = 'light'
    vim.cmd.colorscheme('everforest')
  else
    vim.o.background = 'dark'
    vim.cmd.colorscheme('kanagawa-wave')
  end
end)

Config.now(function()
  local function jdtls_cache_directory()
    return vim.fn.stdpath('cache') .. '/jdtls'
  end

  local function jdtls_workspace_directory()
    return jdtls_cache_directory() .. '/workspace'
  end

  local function jdtls_jvm_arguments()
    local args = {}
    for argument in string.gmatch(os.getenv('JDTLS_JVM_ARGS') or '', '%S+') do
      table.insert(args, string.format('--jvm-arg=%s', argument))
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
    root_markers = {
      'build.sbt',
      'build.sc',
      { 'build.gradle', 'build.gradle.kts' },
      'pom.xml',
      'flake.nix',
      '.git',
    },
  })

  vim.lsp.config('nixd', {
    cmd = { 'nixd' },
    filetypes = { 'nix' },
    root_markers = { 'flake.nix', '.git' },
  })

  local primary_jdtls_root_markers = {
    'mvnw',
    'gradlew',
    'settings.gradle',
    'settings.gradle.kts',
    '.git',
  }
  local secondary_jdtls_root_markers = {
    'build.xml',
    'pom.xml',
    'build.gradle',
    'build.gradle.kts',
    'flake.nix',
  }

  vim.lsp.config('jdtls', {
    cmd = function(dispatchers, lsp_config)
      local data_directory = jdtls_workspace_directory()
      if lsp_config.root_dir then
        data_directory = data_directory .. '/' .. vim.fn.fnamemodify(lsp_config.root_dir, ':p:h:t')
      end
      local command = { 'jdtls', '-data', data_directory, jdtls_jvm_arguments() }
      return vim.lsp.rpc.start(command, dispatchers, {
        cwd = lsp_config.cmd_cwd,
        env = lsp_config.cmd_env,
        detached = lsp_config.detached,
      })
    end,
    filetypes = { 'java' },
    root_markers = { primary_jdtls_root_markers, secondary_jdtls_root_markers },
    init_options = {},
  })

  vim.lsp.enable({ 'metals', 'html', 'jdtls', 'marksman', 'nixd' })
end)
