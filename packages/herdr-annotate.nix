{
  bash,
  fetchFromGitHub,
  fetchurl,
  lib,
  makeWrapper,
  stdenv,
}: let
  version = "0.5.0";
  revision = "d02b0b42cf1955a3b206959659f1833622f213b8";
  plannotatorTuiVersion = "0.9.2";
  herdrAnnotateVersion = "0.1.0";
  herdrAnnotateBinary = fetchurl {
    url = "https://github.com/plannotator/herdr-annotate/releases/download/rust-lite-v${herdrAnnotateVersion}/herdr-annotate-aarch64-apple-darwin";
    hash = "sha256-IjQ5Khzt9LCwVhtMpU2nWqUTnfKW29Tlk3HPf6IB+rc=";
  };
  plannotatorTuiBinary =
    if stdenv.hostPlatform.system == "aarch64-darwin"
    then
      fetchurl {
        url = "https://github.com/plannotator/plannotator-tui/releases/download/v${plannotatorTuiVersion}/plannotator-tui-aarch64-apple-darwin";
        hash = "sha256-eciAG6usXNJXA0A2U2u89Rp7TNjQa0N/HoVxNxRSHrA=";
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
      hash = "sha256-ra+iX1QrsaPe0lmbJ+FOxMp2YWP1YsvPUHPoB3HgOqY=";
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
      command = ["bash", "scripts/fetch-herdr-annotate.sh"]

      ' "" \
              --replace-fail '[[build]]
      platforms = ["macos", "linux"]
      command = ["bash", "scripts/fetch-plannotator-tui.sh"]

      ' "" \
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
      install -Dm755 ${herdrAnnotateBinary} "$pluginRoot/bin/herdr-annotate.exe"
      printf '%s' "${herdrAnnotateVersion}" > "$pluginRoot/bin/herdr-annotate.version"
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
