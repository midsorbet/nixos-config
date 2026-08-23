{pkgs}: let
  inherit (pkgs) lib stdenvNoCC;
  version = "0.12.0";
  sources = {
    "aarch64-darwin" = {
      name = "rem-darwin-arm64.tar.gz";
      hash = "sha256-n2uCdR8nDU6L0MTTAwfJHW1AvTs2Lk2Ezlj0JH2JBN8=";
    };
    "x86_64-darwin" = {
      name = "rem-darwin-amd64.tar.gz";
      hash = "sha256-2pHKdDx6NlK/5D9XP4XWFESC7EP9QUcbB6AbLMh/iVo=";
    };
  };
  source =
    sources.${pkgs.stdenv.hostPlatform.system}
    or (throw "rem is not packaged for ${pkgs.stdenv.hostPlatform.system}");
in
  stdenvNoCC.mkDerivation {
    pname = "rem";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/BRO3886/rem/releases/download/v${version}/${source.name}";
      hash = source.hash;
    };
    sourceRoot = ".";

    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [pkgs.makeWrapper];

    installPhase = ''
      runHook preInstall
      install -Dm755 rem "$out/bin/rem"
      wrapProgram "$out/bin/rem" --set REM_NO_UPDATE_CHECK 1
      runHook postInstall
    '';

    meta = {
      description = "Fast macOS Reminders CLI backed by EventKit";
      homepage = "https://github.com/BRO3886/rem";
      changelog = "https://github.com/BRO3886/rem/releases/tag/v${version}";
      license = lib.licenses.mit;
      mainProgram = "rem";
      platforms = builtins.attrNames sources;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
