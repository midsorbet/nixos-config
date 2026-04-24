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

    meta = mdfriedUnwrapped.meta;
    passthru = {
      inherit configFile configHome defaultSettings;
      unwrapped = mdfriedUnwrapped;
    };
  }
