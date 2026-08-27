-- Nix-specific MiniMax customizations: appearance and managed language servers.

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
    settings = {
      metals = {
        scalafixLintEnabled = true,
      },
    },
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
