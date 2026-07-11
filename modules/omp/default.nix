{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.omp;

  assetSrc = pkgs.fetchzip {
    url = "https://github.com/can1357/oh-my-pi/archive/refs/tags/v${cfg.package.version}.tar.gz";
    hash = "sha256-OZu9KHYvaoYJ+Xbiu+Oocr+PWrXXrf68DFUGfMkRFXA=";
  };
  runtimePath = lib.makeBinPath ([cfg.pythonPackage cfg.bunPackage cfg.uvPackage] ++ cfg.extraRuntimePackages);
  papercutReviewScript = pkgs.writeShellApplication {
    name = "omp-papercut-review";

    text = ''
      set -euo pipefail

      export HOME="/Users/${cfg.user}"
      export USER="${cfg.user}"
      export PATH="${lib.makeBinPath [wrappedPackage cfg.bunPackage]}:/usr/bin:/bin:/usr/sbin:/sbin"

      log_dir="$HOME/Library/Logs/omp"
      project_path=${lib.escapeShellArg cfg.papercutReview.projectPath}
      mkdir -p "$log_dir"
      exec >> "$log_dir/papercut-review.log" 2>&1

      echo "== $(date '+%Y-%m-%d %H:%M:%S') OMP papercut review =="
      cd "$project_path"
      exec ${lib.getExe cfg.bunPackage} "$project_path/src/cli.ts" review
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
      default = pkgs.python314;
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

    papercutReview = {
      enable = lib.mkEnableOption "nightly papercut review";

      hour = lib.mkOption {
        type = lib.types.int;
        default = 23;
        description = "Local hour for the papercut review launchd job.";
      };

      minute = lib.mkOption {
        type = lib.types.int;
        default = 30;
        description = "Local minute for the papercut review launchd job.";
      };

      projectPath = lib.mkOption {
        type = lib.types.str;
        default = "/Users/${cfg.user}/vault/projects/omp-papercuts";
        description = "Mutable standalone checkout containing the papercut review CLI.";
      };
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

    launchd.user.agents.omp-papercut-review = lib.mkIf cfg.papercutReview.enable {
      command = "${papercutReviewScript}/bin/omp-papercut-review";
      serviceConfig = {
        RunAtLoad = false;
        StartCalendarInterval = {
          Hour = cfg.papercutReview.hour;
          Minute = cfg.papercutReview.minute;
        };
      };
    };
  };
}
