{pkgs}: let
  inherit (pkgs) lib stdenvNoCC;
  version = "0.3.6";
in
  stdenvNoCC.mkDerivation {
    pname = "remindctl";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/openclaw/remindctl/releases/download/v${version}/remindctl-macos.zip";
      hash = "sha256-d7fS5vMHlmmbtMNbsdkbaSwShNsxJ+ubj/rSSADuILs=";
    };
    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    nativeBuildInputs = [pkgs.unzip];

    installPhase = ''
      runHook preInstall
      install -Dm755 remindctl "$out/bin/remindctl"
      runHook postInstall
    '';

    nativeInstallCheckInputs = [pkgs.versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";

    meta = {
      description = "Apple Reminders CLI backed by public EventKit APIs";
      homepage = "https://github.com/openclaw/remindctl";
      changelog = "https://github.com/openclaw/remindctl/releases/tag/v${version}";
      license = lib.licenses.mit;
      mainProgram = "remindctl";
      platforms = lib.platforms.darwin;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
