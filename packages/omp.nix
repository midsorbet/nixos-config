{pkgs}: let
  inherit (pkgs) lib stdenv;

  version = "16.3.4";
  releaseBaseUrl = "https://github.com/can1357/oh-my-pi/releases/download/v${version}";
  binaries = {
    "aarch64-darwin" = {
      name = "omp-darwin-arm64";
      hash = "sha256-soPwaXaytyPIwh5L7nCcTFMpIlaoSDcfch7m+gVcr9Y=";
    };
  };
  binary =
    binaries.${stdenv.hostPlatform.system}
    or (throw "omp is not packaged for ${stdenv.hostPlatform.system}");
in
  stdenv.mkDerivation {
    pname = "omp";
    inherit version;

    src = pkgs.fetchurl {
      url = "${releaseBaseUrl}/${binary.name}";
      hash = binary.hash;
    };

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/omp"
      runHook postInstall
    '';

    postInstall = ''
      install -d "$out/share/bash-completion/completions"
      install -d "$out/share/fish/vendor_completions.d"
      install -d "$out/share/zsh/site-functions"

      HOME="$TMPDIR" "$out/bin/omp" completions bash > "$out/share/bash-completion/completions/omp"
      HOME="$TMPDIR" "$out/bin/omp" completions fish > "$out/share/fish/vendor_completions.d/omp.fish"
      HOME="$TMPDIR" "$out/bin/omp" completions zsh > "$out/share/zsh/site-functions/_omp"
    '';

    nativeInstallCheckInputs = [pkgs.versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";

    meta = with lib; {
      description = "Oh My Pi terminal coding agent";
      homepage = "https://omp.sh/";
      changelog = "https://github.com/can1357/oh-my-pi/releases/tag/v${version}";
      license = licenses.mit;
      mainProgram = "omp";
      platforms = attrNames binaries;
      sourceProvenance = [sourceTypes.binaryNativeCode];
    };
  }
