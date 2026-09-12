{pkgs}: let
  inherit (pkgs) lib stdenv;
  version = "0.27.12";
  releaseBaseUrl = "https://github.com/backnotprop/plannotator/releases/download/v${version}";
  binaries = {
    "aarch64-darwin" = {
      name = "plannotator-darwin-arm64";
      hash = "sha256-8LLfK1XZXJaRKJHOmbK72skY3y1jVMSmZJ5V+ExdcCk=";
    };
    "x86_64-darwin" = {
      name = "plannotator-darwin-x64";
      hash = "sha256-QWE/o4mpnXKCmw8IRMPVu8yMprcK1OHuJKvY6KM1dtc=";
    };
    "aarch64-linux" = {
      name = "plannotator-linux-arm64";
      hash = "sha256-5gP6u+lFk4v06fwvAuwEEs9wZlhZ/+PKAUwiHIKqEBk=";
    };
    "x86_64-linux" = {
      name = "plannotator-linux-x64";
      hash = "sha256-R5uicXyqLad+Lhiwo9YfQldHzl+mh7JBN4Qr1VV09m0=";
    };
  };

  sourceSrc = pkgs.fetchFromGitHub {
    owner = "backnotprop";
    repo = "plannotator";
    rev = "v${version}";
    hash = "sha256-Z3k/YnGXB/OGL3BP+2Z/Ck1H28rJeA+ihdZ8EaXKwIA=";
  };
  localSkills = ./plannotator-skills;

  skills = stdenv.mkDerivation {
    pname = "plannotator-skills";
    inherit version;

    src = sourceSrc;

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/agents/skills"
      cp -R apps/skills/core/plannotator-annotate "$out/share/agents/skills/"
      cp -R apps/skills/core/plannotator-last "$out/share/agents/skills/"
      cp -R apps/skills/core/plannotator-review "$out/share/agents/skills/"
      for skill in plannotator-annotate plannotator-last plannotator-review; do
        chmod -R u+w "$out/share/agents/skills/$skill"
        cp -R "${localSkills}/$skill/." "$out/share/agents/skills/$skill/"
      done
      runHook postInstall
    '';
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

    nativeBuildInputs =
      [pkgs.makeWrapper]
      ++ lib.optionals stdenv.hostPlatform.isLinux [pkgs.autoPatchelfHook];

    dontFixup = stdenv.hostPlatform.isDarwin;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/.plannotator-unwrapped"
      makeWrapper "$out/bin/.plannotator-unwrapped" "$out/bin/plannotator" \
        --set PLANNOTATOR_SHARE disabled
      runHook postInstall
    '';

    nativeInstallCheckInputs = [pkgs.versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";

    passthru = {
      inherit skills;
    };
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
