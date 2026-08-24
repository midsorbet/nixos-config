{pkgs}: let
  inherit (pkgs) lib stdenv;
  version = "0.27.8";
  releaseBaseUrl = "https://github.com/backnotprop/plannotator/releases/download/v${version}";
  binaries = {
    "aarch64-darwin" = {
      name = "plannotator-darwin-arm64";
      hash = "sha256-E71OrlkWwRksP3H9TIcigp1wdueBhQ/WoO8v/G8WzGs=";
    };
    "x86_64-darwin" = {
      name = "plannotator-darwin-x64";
      hash = "sha256-JTPHhCM9pECYhEtwcHq29FOSClRDqdvZW7+ONJrInhs=";
    };
    "aarch64-linux" = {
      name = "plannotator-linux-arm64";
      hash = "sha256-tXNU/Yy5ytasCS8IaY//ZZw2xGkNId11XDyANu7qLxU=";
    };
    "x86_64-linux" = {
      name = "plannotator-linux-x64";
      hash = "sha256-owcUKEOYRvwqtoBGfrYZwsipAidcKKepZxk69XU7F9Y=";
    };
  };

  sourceSrc = pkgs.fetchFromGitHub {
    owner = "backnotprop";
    repo = "plannotator";
    rev = "v${version}";
    hash = "sha256-0BuR0+yDBJdv65grQPblhabb24a99tQhqq5EOIkO3bQ=";
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
