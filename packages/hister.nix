{
  fetchurl,
  lib,
  rcodesign,
  stdenv,
  versionCheckHook,
}: let
  version = "0.19.0";
  releaseBaseUrl = "https://github.com/asciimoo/hister/releases/download/v${version}";
  binaries = {
    "aarch64-darwin" = {
      name = "hister_${version}_darwin_arm64";
      hash = "sha256-5/axOoMuIeOdKfPZ0PV7zez1rIMrpq7x/CoSBN6W8d4=";
    };
    "x86_64-linux" = {
      name = "hister_${version}_linux_amd64";
      hash = "sha256-dXH3uUA5kX1Rk3L6av8Y/hLC71D5gayEfsGv9NfkFwE=";
    };
  };
  binary =
    binaries.${stdenv.hostPlatform.system}
    or (throw "Hister is not packaged for ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "hister";
    inherit version;

    src = fetchurl {
      url = "${releaseBaseUrl}/${binary.name}";
      inherit (binary) hash;
    };

    dontUnpack = true;
    dontStrip = true;

    nativeBuildInputs = lib.optionals stdenv.hostPlatform.isDarwin [rcodesign];

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/hister"
      ${lib.optionalString stdenv.hostPlatform.isDarwin ''
        rcodesign sign "$out/bin/hister"
      ''}
      runHook postInstall
    '';

    nativeInstallCheckInputs = [versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";

    meta = {
      description = "Private full-text search engine for visited pages and local files";
      homepage = "https://hister.org";
      changelog = "https://github.com/asciimoo/hister/releases/tag/v${version}";
      license = lib.licenses.agpl3Plus;
      mainProgram = "hister";
      platforms = builtins.attrNames binaries;
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  }
