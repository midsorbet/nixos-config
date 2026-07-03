{pkgs}: let
  inherit (pkgs) lib stdenv;

  version = "0.21.4";
  releaseBaseUrl = "https://github.com/backnotprop/plannotator/releases/download/v${version}";
  binaries = {
    "aarch64-darwin" = {
      name = "plannotator-darwin-arm64";
      hash = "sha256-Bhx62zgqwgT0B0h7PQ/EmjWJt5CLhtUw2Jba6rep720=";
    };
    "x86_64-darwin" = {
      name = "plannotator-darwin-x64";
      hash = "sha256-eHRxzju2z/9f2SLzCB5ulkdhDrGHMGqiNdMDrg02nQw=";
    };
    "aarch64-linux" = {
      name = "plannotator-linux-arm64";
      hash = "sha256-/EG+jPtnPUTrmi6xfgShJc58tp8EmDayILk4tKYFsIs=";
    };
    "x86_64-linux" = {
      name = "plannotator-linux-x64";
      hash = "sha256-19wZGFRAvQfXNWgwlAsFJoFhLyUhSFi+068bcv0asuA=";
    };
  };
  binary =
    binaries.${stdenv.hostPlatform.system}
    or (throw "plannotator is not packaged for ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "plannotator";
    inherit version;

    src = pkgs.fetchurl {
      url = "${releaseBaseUrl}/${binary.name}";
      hash = binary.hash;
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;
    dontFixup = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/plannotator"
      runHook postInstall
    '';

    nativeInstallCheckInputs = [pkgs.versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";

    meta = with lib; {
      description = "Interactive browser-based plan and code review surface for AI coding agents";
      homepage = "https://github.com/backnotprop/plannotator";
      changelog = "https://github.com/backnotprop/plannotator/releases/tag/v${version}";
      license = with licenses; [mit asl20];
      mainProgram = "plannotator";
      platforms = attrNames binaries;
      sourceProvenance = [sourceTypes.binaryNativeCode];
    };
  }
