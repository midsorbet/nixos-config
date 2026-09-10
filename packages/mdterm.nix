{
  fetchFromGitHub,
  formats,
  lib,
  makeWrapper,
  runCommand,
  rustPlatform,
  settings ? {},
  stdenvNoCC,
}: let
  version = "2.0.0-unstable-2026-09-10";
  mdtermUnwrapped = rustPlatform.buildRustPackage {
    pname = "mdterm";
    inherit version;

    src = fetchFromGitHub {
      owner = "bahdotsh";
      repo = "mdterm";
      rev = "5560db756e60766bca79c61b86dc20c34ce14850";
      hash = "sha256-jjYxndaHTitWAQ5MaMMCosVT7yU4m7PKgmbd7Vhj+lQ=";
    };

    cargoHash = "sha256-YUPKUFfbzL/1peXEAX5EDehWq4hFwxJLkP2DBDkY23E=";

    meta = {
      description = "Terminal-based Markdown viewer with syntax highlighting and interactive navigation";
      homepage = "https://github.com/bahdotsh/mdterm";
      license = lib.licenses.mit;
      mainProgram = "mdterm";
      platforms = lib.platforms.darwin ++ lib.platforms.linux;
    };
  };
  defaultSettings = {
    theme = "light";
  };
  configFile = (formats.toml {}).generate "mdterm-config.toml" (lib.recursiveUpdate defaultSettings settings);
  configHome = runCommand "mdterm-config-home" {} ''
    mkdir -p "$out/mdterm"
    cp ${configFile} "$out/mdterm/config.toml"
  '';
in
  stdenvNoCC.mkDerivation {
    pname = "mdterm";
    inherit version;

    dontUnpack = true;
    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin"
      makeWrapper ${mdtermUnwrapped}/bin/mdterm "$out/bin/mdterm" \
        --set XDG_CONFIG_HOME ${lib.escapeShellArg configHome}

      runHook postInstall
    '';

    inherit (mdtermUnwrapped) meta;
    passthru = {
      inherit configFile configHome defaultSettings;
      unwrapped = mdtermUnwrapped;
    };
  }
