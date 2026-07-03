{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.omp;

  assetSrc = pkgs.fetchzip {
    url = "https://github.com/can1357/oh-my-pi/archive/refs/tags/v${cfg.package.version}.tar.gz";
    hash = "sha256-wPPBgNUCa4gt4BGKU1Q7Fnm/FRecagJ6KYQqo0+Yk/Q=";
  };
  runtimePath = lib.makeBinPath ([cfg.pythonPackage cfg.bunPackage cfg.uvPackage] ++ cfg.extraRuntimePackages);

  managedNpmPluginsArgs = lib.concatMapStringsSep " " lib.escapeShellArg cfg.managedNpmPlugins;

  pluginInstalledCheck = pkgs.writeText "omp-plugin-installed.py" ''
    import json
    import os
    import sys

    try:
        data = json.loads(os.environ.get("PLUGIN_JSON", ""))
    except Exception:
        sys.exit(1)

    for plugin in data.get("npm", []):
        if (
            plugin.get("name") == os.environ["PLUGIN_NAME"]
            and plugin.get("version") == os.environ["PLUGIN_VERSION"]
            and plugin.get("enabled", True)
        ):
            sys.exit(0)

    sys.exit(1)
  '';

  installManagedNpmPlugins = pkgs.writeShellApplication {
    name = "omp-install-managed-npm-plugins";
    runtimeInputs = [wrappedPackage cfg.bunPackage cfg.pythonPackage];
    text = ''
      set -u

      export HOME=${lib.escapeShellArg config.hjem.users.${cfg.user}.directory}
      plugins=(${managedNpmPluginsArgs})

      if [ "''${#plugins[@]}" -eq 0 ]; then
        exit 0
      fi

      installed_json="$(omp plugin list --json 2>/dev/null || true)"

      for spec in "''${plugins[@]}"; do
        name="''${spec%@*}"
        version="''${spec##*@}"

        if [ -z "$name" ] || [ "$name" = "$spec" ]; then
          echo "warning: managed OMP plugin spec must include an explicit version: $spec" >&2
          continue
        fi

        if PLUGIN_JSON="$installed_json" PLUGIN_NAME="$name" PLUGIN_VERSION="$version" python3 ${pluginInstalledCheck}; then
          echo "OMP plugin already installed: $spec"
          continue
        fi

        echo "Installing managed OMP plugin: $spec"
        if omp install "$spec"; then
          installed_json="$(omp plugin list --json 2>/dev/null || true)"
        else
          echo "warning: failed to install managed OMP plugin: $spec" >&2
        fi
      done

      exit 0
    '';
  };

  wrappedPackage =
    pkgs.runCommand "omp-${cfg.package.version}-with-runtimes" {
      nativeBuildInputs = [pkgs.makeWrapper];
    } ''
      mkdir -p "$out/bin"

      mkdir -p "$out/share"
      cp -R ${cfg.package}/share/. "$out/share/"
      mkdir -p "$out/share/omp"
      cp -R ${assetSrc}/docs "$out/share/omp/docs"
      cp -R ${assetSrc}/packages/coding-agent/examples "$out/share/omp/examples"
      cp ${assetSrc}/packages/coding-agent/CHANGELOG.md "$out/share/omp/CHANGELOG.md"
      cp ${assetSrc}/packages/coding-agent/README.md "$out/share/omp/README.md"

      makeWrapper ${lib.getExe cfg.package} "$out/bin/omp" \
        --prefix PATH : ${lib.escapeShellArg runtimePath} \
        --set-default PI_PY 1 \
        --set-default PI_JS 1 \
        --set-default PI_PACKAGE_DIR "$out/share/omp"
    '';

  mkTheme = {
    name,
    background,
    text,
    accent,
    secondary,
    success,
    error,
    warning,
    muted,
    dim,
    selectedBg,
    statusLineBg,
  }: {
    inherit name;
    colors = {
      accent = accent;
      border = muted;
      borderAccent = secondary;
      borderMuted = dim;
      success = success;
      error = error;
      warning = warning;
      muted = muted;
      dim = dim;
      text = text;
      thinkingText = muted;

      selectedBg = selectedBg;
      userMessageBg = selectedBg;
      customMessageBg = selectedBg;
      toolPendingBg = selectedBg;
      toolSuccessBg = statusLineBg;
      toolErrorBg = selectedBg;
      statusLineBg = statusLineBg;

      userMessageText = text;
      customMessageText = text;
      customMessageLabel = secondary;
      toolTitle = text;
      toolOutput = text;

      mdHeading = accent;
      mdLink = accent;
      mdLinkUrl = secondary;
      mdCode = warning;
      mdCodeBlock = text;
      mdCodeBlockBorder = muted;
      mdQuote = muted;
      mdQuoteBorder = dim;
      mdHr = dim;
      mdListBullet = secondary;

      toolDiffAdded = success;
      toolDiffRemoved = error;
      toolDiffContext = muted;
      syntaxComment = muted;
      syntaxKeyword = secondary;
      syntaxFunction = accent;
      syntaxVariable = text;
      syntaxString = success;
      syntaxNumber = warning;
      syntaxType = accent;
      syntaxOperator = secondary;
      syntaxPunctuation = dim;

      thinkingOff = dim;
      thinkingMinimal = muted;
      thinkingLow = accent;
      thinkingMedium = success;
      thinkingHigh = warning;
      thinkingXhigh = error;
      bashMode = warning;
      pythonMode = accent;

      statusLineSep = dim;
      statusLineModel = accent;
      statusLinePath = text;
      statusLineGitClean = success;
      statusLineGitDirty = warning;
      statusLineContext = secondary;
      statusLineSpend = warning;
      statusLineStaged = accent;
      statusLineDirty = warning;
      statusLineUntracked = error;
      statusLineOutput = secondary;
      statusLineCost = error;
      statusLineSubagents = success;
    };
    export = {
      pageBg = background;
      cardBg = selectedBg;
      infoBg = statusLineBg;
    };
    symbols.preset = "unicode";
  };

  kanagawaWaveTheme = mkTheme {
    name = "kanagawa-wave";
    background = "#1f1f28";
    text = "#dcd7ba";
    accent = "#7e9cd8";
    secondary = "#957fb8";
    success = "#98bb6c";
    error = "#c34043";
    warning = "#e6c384";
    muted = "#727169";
    dim = "#54546d";
    selectedBg = "#2a2a37";
    statusLineBg = "#090618";
  };

  everforestLightHardTheme = mkTheme {
    name = "everforest-light-hard";
    background = "#f2efdf";
    text = "#5c6a72";
    accent = "#7fbbb3";
    secondary = "#d699b6";
    success = "#9ab373";
    error = "#e67e80";
    warning = "#ceaf72";
    muted = "#a6b0a0";
    dim = "#b2af9f";
    selectedBg = "#f0f2d4";
    statusLineBg = "#e5dfc5";
  };
in {
  options.local.omp = {
    enable = lib.mkEnableOption "global OMP with Nix-provided eval runtimes";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should receive the Hjem-managed OMP package and config.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.omp;
      description = "OMP package to wrap and install.";
    };

    pythonPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.python313;
      description = "Python interpreter made available to OMP eval cells.";
    };

    bunPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.bun;
      description = "Bun runtime made available to OMP and its tool subprocesses.";
    };

    uvPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.uv;
      description = "uv package manager made available to OMP and its tool subprocesses.";
    };

    managedNpmPlugins = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
      description = "Version-pinned npm plugins that OMP should ensure exist in the user's mutable plugin directory.";
    };

    extraRuntimePackages = lib.mkOption {
      type = with lib.types; listOf package;
      default = [];
      description = "Additional packages to prepend to PATH for OMP runtime and tool subprocesses.";
    };

    settingsFile = lib.mkOption {
      type = lib.types.path;
      default = ./config.yml;
      description = "YAML config file linked to ~/.omp/agent/config.yml.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [wrappedPackage];

    hjem.users.${cfg.user} = {
      files = {
        ".omp/agent/config.yml" = {
          source = cfg.settingsFile;
          clobber = true;
        };
        ".omp/agent/themes/kanagawa-wave.json" = {
          text = builtins.toJSON kanagawaWaveTheme;
          clobber = true;
        };
        ".omp/agent/themes/everforest-light-hard.json" = {
          text = builtins.toJSON everforestLightHardTheme;
          clobber = true;
        };
      };
    };

    launchd.user.agents.omp-install-managed-npm-plugins = lib.mkIf (cfg.managedNpmPlugins != []) {
      serviceConfig = {
        ProgramArguments = ["${installManagedNpmPlugins}/bin/omp-install-managed-npm-plugins"];
        RunAtLoad = true;
        StandardOutPath = "${config.hjem.users.${cfg.user}.directory}/Library/Logs/omp-install-managed-npm-plugins.log";
        StandardErrorPath = "${config.hjem.users.${cfg.user}.directory}/Library/Logs/omp-install-managed-npm-plugins.log";
        EnvironmentVariables = {
          HOME = config.hjem.users.${cfg.user}.directory;
        };
      };
    };
  };
}
