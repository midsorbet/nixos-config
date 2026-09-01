{
  bash,
  bun,
  fetchFromGitHub,
  fetchurl,
  lib,
  makeWrapper,
  stdenv,
}: let
  version = "0.3.0";
  revision = "bccf884b874f5f39ccbef1bb6ac67625c5fb5d54";
  plannotatorTuiVersion = "0.6.0";
  plannotatorTuiBinary =
    if stdenv.hostPlatform.system == "aarch64-darwin"
    then
      fetchurl {
        url = "https://github.com/plannotator/plannotator-tui/releases/download/v${plannotatorTuiVersion}/plannotator-tui-aarch64-apple-darwin";
        hash = "sha256-CW0MWr2oYsFzrHN5xgb4kJdo9DRYMzrHBr1u3gQkyLc=";
      }
    else throw "herdr-annotate is not packaged for ${stdenv.hostPlatform.system}";
in
  stdenv.mkDerivation {
    pname = "herdr-annotate";
    inherit version;

    src = fetchFromGitHub {
      owner = "plannotator";
      repo = "herdr-annotate";
      rev = revision;
      hash = "sha256-h3ibUCd2uLtQENU0IRNJzefZH2pnK13mzCoHmGc1EeU=";
    };

    nativeBuildInputs = [makeWrapper];

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontFixup = stdenv.hostPlatform.isDarwin;

    postPatch = ''
          substituteInPlace herdr-plugin.toml \
            --replace-fail '[[build]]
      platforms = ["macos", "linux"]
      command = ["bash", "scripts/fetch-plannotator-tui.sh"]

      ' "" \
            --replace-fail 'command = ["bun",' 'command = ["${lib.getExe bun}",' \
            --replace-fail 'command = ["sh",' 'command = ["${lib.getExe bash}",' \
            --replace-fail 'exec bash \"' 'exec ${lib.getExe bash} \"'
    '';

    installPhase = ''
      runHook preInstall

      pluginRoot="$out/share/herdr/plugins/annotate"
      mkdir -p "$pluginRoot" "$out/bin" "$out/libexec/herdr-annotate"
      cp -R . "$pluginRoot/"

      install -Dm755 ${plannotatorTuiBinary} \
        "$out/libexec/herdr-annotate/plannotator-tui-unwrapped"
      makeWrapper \
        "$out/libexec/herdr-annotate/plannotator-tui-unwrapped" \
        "$out/bin/plannotator-tui" \
        --run 'if [ "''${PLANNOTATOR_TUI_HOST:-}" = omp ]; then export PLANNOTATOR_TUI_HOST=pi; export PI_CODING_AGENT_DIR="$HOME/.omp/agent"; fi'

      rm -f "$pluginRoot/bin/.gitkeep"
      ln -s "$out/bin/plannotator-tui" "$pluginRoot/bin/plannotator-tui.exe"
      printf '%s' "${plannotatorTuiVersion}" > "$pluginRoot/bin/plannotator-tui.version"
      mkdir -p "$out/share/agents/skills"
      ln -s "$pluginRoot/skills/plannotator-tui" \
        "$out/share/agents/skills/plannotator-tui"

      runHook postInstall
    '';

    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      versionOutput="$($out/bin/plannotator-tui --version)"
      case "$versionOutput" in
        *"${plannotatorTuiVersion}"*) ;;
        *)
          echo "Unexpected plannotator-tui version: $versionOutput" >&2
          exit 1
          ;;
      esac
      runHook postInstallCheck
    '';

    meta = {
      description = "Herdr terminal annotation and Plannotator TUI integration";
      homepage = "https://github.com/plannotator/herdr-annotate";
      license = lib.licenses.mit;
      mainProgram = "plannotator-tui";
      platforms = ["aarch64-darwin"];
      sourceProvenance = with lib.sourceTypes; [
        fromSource
        binaryNativeCode
      ];
    };
  }
