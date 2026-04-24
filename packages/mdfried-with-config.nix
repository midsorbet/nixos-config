{
  formats,
  lib,
  makeWrapper,
  mdfried,
  runCommand,
  stdenv,
  stdenvNoCC,
  settings,
}: let
  configFile = (formats.toml {}).generate "mdfried-config.toml" settings;
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
    pname = "mdfried-with-config";
    version = mdfried.version;

    dontUnpack = true;
    nativeBuildInputs = [makeWrapper];

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin"
      makeWrapper ${mdfried}/bin/mdfried "$out/bin/mdfried" ${configEnvFlag}

      runHook postInstall
    '';

    meta = mdfried.meta;
    passthru = {
      inherit configFile configHome;
      unwrapped = mdfried;
    };
  }
