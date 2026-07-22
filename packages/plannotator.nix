{pkgs}: let
  inherit (pkgs) lib stdenv;

  version = "0.24.2";
  releaseBaseUrl = "https://github.com/backnotprop/plannotator/releases/download/v${version}";
  binaries = {
    "aarch64-darwin" = {
      name = "plannotator-darwin-arm64";
      hash = "sha256-1ZCht4axKZol0iizDVuXMHpztPjzxMyt5Z9AsC+J8V0=";
    };
    "x86_64-darwin" = {
      name = "plannotator-darwin-x64";
      hash = "sha256-kw9Slut12IX0S/8hMj4X+HYnapO58KDCQ/7GXS+0OKo=";
    };
    "aarch64-linux" = {
      name = "plannotator-linux-arm64";
      hash = "sha256-jJkVjFxWj6lqBojruLBiRpBfvZNnaJ/LZmpqRx+u1KU=";
    };
    "x86_64-linux" = {
      name = "plannotator-linux-x64";
      hash = "sha256-6cyScQhh/1hD8XQmst/I4NKWEwxmciRBAejBUy8f2A0=";
    };
  };

  sourceSrc = pkgs.fetchFromGitHub {
    owner = "backnotprop";
    repo = "plannotator";
    rev = "v${version}";
    hash = "sha256-QiHKiHePxCRwGAS0/jh5sq5eAJnpqMhY3hjFWzvcfuE=";
  };

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
      cp -R apps/skills/extra/plannotator-setup-goal "$out/share/agents/skills/"
      cp -R apps/skills/extra/plannotator-visual-explainer "$out/share/agents/skills/"
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
