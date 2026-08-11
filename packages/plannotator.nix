{pkgs}: let
  inherit (pkgs) lib stdenv;
  version = "0.26.8";
  releaseBaseUrl = "https://github.com/backnotprop/plannotator/releases/download/v${version}";
  binaries = {
    "aarch64-darwin" = {
      name = "plannotator-darwin-arm64";
      hash = "sha256-SZDwodC2rXrj6qKpFzfqxlXc5fUJZTF7tncfgvRDlFU=";
    };
    "x86_64-darwin" = {
      name = "plannotator-darwin-x64";
      hash = "sha256-JUWCEyzmcPgMxErf8rphO5f1T8giwE7CokpB/BIqHsc=";
    };
    "aarch64-linux" = {
      name = "plannotator-linux-arm64";
      hash = "sha256-FcGurfrvSYCzoG3NAT6MhVtpkjwGRBc4VLG5UVTUSIs=";
    };
    "x86_64-linux" = {
      name = "plannotator-linux-x64";
      hash = "sha256-T4txYRxYY/OUZL9hs7uRUdU2ZE/w6Eh//BZfyt7Es4A=";
    };
  };

  sourceSrc = pkgs.fetchFromGitHub {
    owner = "backnotprop";
    repo = "plannotator";
    rev = "v${version}";
    hash = "sha256-suD7OFZ2NrdW0fT6MJ+4cdbI1Bl1D75FDoNowHQDr+k=";
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
