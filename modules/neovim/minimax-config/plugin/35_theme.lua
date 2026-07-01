-- Local mini-darwin theme selection.
Config.now(function()
  vim.pack.add({
    'https://github.com/sainnhe/everforest',
    'https://github.com/rebelot/kanagawa.nvim',
  })

  vim.g.everforest_background = 'hard'
  vim.g.everforest_better_performance = 1

  local macos_uses_light = function()
    if vim.fn.has('mac') ~= 1 then return vim.o.background == 'light' end

    local output = vim.fn.system({ 'defaults', 'read', '-g', 'AppleInterfaceStyle' })
    return vim.v.shell_error ~= 0 or not output:match('Dark')
  end

  local apply_theme = function()
    if macos_uses_light() then
      vim.o.background = 'light'
      vim.cmd('colorscheme everforest')
    else
      vim.o.background = 'dark'
      vim.cmd('colorscheme kanagawa-wave')
    end
  end

  Config.new_autocmd('FocusGained', nil, apply_theme, 'Sync color scheme with macOS appearance')
  apply_theme()
end)
