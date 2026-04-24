{
  formats,
  lib,
  makeWrapper,
  mdfriedInput,
  runCommand,
  stdenv,
  stdenvNoCC,
  settings ? {},
}: let
  mdfriedUnwrapped = mdfriedInput.packages."${stdenv.hostPlatform.system}".default.overrideAttrs (_:
    lib.optionalAttrs stdenv.hostPlatform.isDarwin {
      doCheck = false;
    });
  defaultSettings = {
    font_family = "JetBrainsMono Nerd Font";
    max_image_height = 30;
    watch_debounce_milliseconds = 100;
    enable_mouse_capture = false;

    padding = {
      type = "centered";
      value = 100;
    };
  };
  configFile = (formats.toml {}).generate "mdfried-config.toml" (lib.recursiveUpdate defaultSettings settings);
  configHome =
    if stdenv.hostPlatform.isDarwin
    then
      runCommand "mdfried-config-home" {} ''
        mkdir -p "$out/Library/Application Support/rs.mdfried"
        cp ${configFile} "$out/Library/Application Support/rs.mdfried/config.toml"
      ''
    else if stdenv.hostPlatform.isLinux
    then
      runCommand "mdfried-config-home" {} ''
        mkdir -p "$out/mdfried"
        cp ${configFile} "$out/mdfried/config.toml"
      ''
    else throw "mdfried config wrapper is only defined for Darwin and Linux";
  configEnvFlag =
    if stdenv.hostPlatform.isDarwin
    then "--set HOME ${lib.escapeShellArg configHome}"
    else "--set XDG_CONFIG_HOME ${lib.escapeShellArg configHome}";
in
  stdenvNoCC.mkDerivation {
    pname = "mdfried";
    version = mdfriedUnwrapped.version;

    dontUnpack = true;
    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin"
      makeWrapper ${mdfriedUnwrapped}/bin/mdfried "$out/bin/mdfried" ${configEnvFlag}

      runHook postInstall
    '';

    meta =
      mdfriedUnwrapped.meta
      // {
        description = "A markdown viewer for the terminal that renders images and big headers";
        longDescription = ''
          mdfried renders Markdown in the terminal with large headers and inline
          images. It can use terminal graphics protocols such as Sixel, Kitty,
          and iTerm2, Kitty's text sizing protocol, or Chafa as a fallback on
          terminals without graphics support.
        '';
        homepage = "https://github.com/benjajaja/mdfried";
        changelog = "https://github.com/benjajaja/mdfried/blob/v${mdfriedUnwrapped.version}/CHANGELOG.md";
        downloadPage = "https://github.com/benjajaja/mdfried/releases";
        license = lib.licenses.gpl3Plus;
        mainProgram = "mdfried";
        platforms = lib.platforms.darwin ++ lib.platforms.linux;
      };
    passthru = {
      inherit configFile configHome defaultSettings;
      unwrapped = mdfriedUnwrapped;
    };
  }
