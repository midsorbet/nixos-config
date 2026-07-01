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

  minimaxConfig = pkgs.runCommand "minimax-nvim-config" {nativeBuildInputs = [pkgs.jq];} ''
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

        lsp_enable_placeholder="$(cat <<'EOF'
      -- vim.lsp.enable({
      --   -- For example, if `lua-language-server` is installed, use `'lua_ls'` entry
      -- })
    EOF
    )"
        lsp_enable_block="$(cat <<'EOF'
      vim.lsp.enable({
        'metals',
        'html',
        'jdtls',
        'marksman',
      })
    EOF
    )"
        substituteInPlace "$out/plugin/40_plugins.lua" \
          --replace-fail "$lsp_enable_placeholder" "$lsp_enable_block"

        lockfile="$out/nvim-pack-lock.json"
        jq '.plugins += {
          "everforest": {
            "rev": "85a86eb62409e3ec88713bff3d1b9d7374e112e4",
            "src": "https://github.com/sainnhe/everforest"
          },
          "kanagawa.nvim": {
            "rev": "bb85e4bfc8d89b0e62c8fa53ccdd13d12e2f77b3",
            "src": "https://github.com/rebelot/kanagawa.nvim"
          }
        }' "$lockfile" > "$lockfile.tmp"
        mv "$lockfile.tmp" "$lockfile"

        cat > "$out/plugin/35_theme.lua" <<'EOF'
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
    EOF

        cat > "$out/after/lsp/metals.lua" <<'EOF'
    -- Load project flake dev-shell environment when one is present.
    return {
      cmd = { '${lib.getExe metalsWrapper}' },
      filetypes = { 'scala', 'sbt' },
      root_markers = { 'build.sbt', 'build.sc', { 'build.gradle', 'build.gradle.kts' }, 'pom.xml', 'flake.nix', '.git' },
    }
    EOF

        cat > "$out/after/lsp/html.lua" <<'EOF'
    return {
      cmd = { '${pkgs.vscode-langservers-extracted}/bin/vscode-html-language-server', '--stdio' },
    }
    EOF

        cat > "$out/after/lsp/jdtls.lua" <<'EOF'
    local function get_jdtls_cache_dir()
      return vim.fn.stdpath('cache') .. '/jdtls'
    end

    local function get_jdtls_workspace_dir()
      return get_jdtls_cache_dir() .. '/workspace'
    end

    local function get_jdtls_jvm_args()
      local env = os.getenv('JDTLS_JVM_ARGS')
      local args = {}
      for a in string.gmatch((env or ""), '%S+') do
        local arg = string.format('--jvm-arg=%s', a)
        table.insert(args, arg)
      end
      return unpack(args)
    end

    local root_markers1 = {
      'mvnw',
      'gradlew',
      'settings.gradle',
      'settings.gradle.kts',
      '.git',
    }
    local root_markers2 = {
      'build.xml',
      'pom.xml',
      'build.gradle',
      'build.gradle.kts',
      'flake.nix',
    }

    return {
      cmd = function(dispatchers, config)
        local workspace_dir = get_jdtls_workspace_dir()
        local data_dir = workspace_dir

        if config.root_dir then
          data_dir = data_dir .. '/' .. vim.fn.fnamemodify(config.root_dir, ':p:h:t')
        end

        local config_cmd = {
          '${lib.getExe jdtlsWrapper}',
          '-data',
          data_dir,
          get_jdtls_jvm_args(),
        }

        return vim.lsp.rpc.start(config_cmd, dispatchers, {
          cwd = config.cmd_cwd,
          env = config.cmd_env,
          detached = config.detached,
        })
      end,
      filetypes = { 'java' },
      root_markers = vim.fn.has('nvim-0.11.3') == 1 and { root_markers1, root_markers2 }
        or vim.list_extend(root_markers1, root_markers2),
      init_options = {},
    }
    EOF

        cat > "$out/after/lsp/marksman.lua" <<'EOF'
    return {
      cmd = { '${lib.getExe pkgs.marksman}', 'server' },
    }
    EOF
  '';

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
    hjem.users.${cfg.user} = {
      packages = [
        metalsWrapper
        jdtlsWrapper
        pkgs.jdk
        pkgs.maven
        pkgs.marksman
        pkgs.vscode-langservers-extracted
      ];

      xdg.config.files."nvim" = {
        type = "symlink";
        source = minimaxConfig;
        clobber = true;
      };
    };
  };
}
