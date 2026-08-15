{
  fetchFromGitHub,
  lib,
  makeWrapper,
  python3,
  stdenvNoCC,
}: let
  pythonRuntime = python3.withPackages (pythonPackages: [pythonPackages.websockets]);
in
  stdenvNoCC.mkDerivation {
    pname = "herdr-remote";
    version = "0.7.3";

    src = fetchFromGitHub {
      owner = "dcolinmorgan";
      repo = "herdr-remote";
      rev = "2f7213111f7262f7b2daf2cd59b5abefff52a925";
      hash = "sha256-ZL3TGot+UP6ihgFDsV2BkmdmdkUZMgRh+19TitlyT0c=";
    };

    patches = [./herdr-remote-hardening.patch];
    nativeBuildInputs = [makeWrapper];
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/bin" "$out/libexec/herdr-remote"
      cp -R relay web "$out/libexec/herdr-remote/"
      makeWrapper ${pythonRuntime}/bin/python3 "$out/bin/herdr-remote" \
        --add-flags "$out/libexec/herdr-remote/relay/herdr_relay.py"

      runHook postInstall
    '';

    meta = {
      description = "Hardened read-only browser relay for Herdr sessions";
      homepage = "https://github.com/dcolinmorgan/herdr-remote";
      license = lib.licenses.agpl3Plus;
      mainProgram = "herdr-remote";
      platforms = lib.platforms.unix;
    };
  }
