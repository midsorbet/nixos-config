{pkgs}: let
  version = "1.0.83";
  releaseBaseUrl = "https://github.com/github/copilot-cli/releases/download/v${version}";
  tarballs = {
    "aarch64-linux" = {
      name = "copilot-linux-arm64";
      hash = "sha256-ITs6JnBC26w82K4iyC9eoE/zyrwAgQjA+JUFXUa+RHM=";
    };
    "x86_64-linux" = {
      name = "copilot-linux-x64";
      hash = "sha256-/74cQpZkuKBe/tZ+zbRnEj5A/Ko8bBTvmpi6dNpGh7c=";
    };
  };
  tarball =
    tarballs.${pkgs.stdenv.hostPlatform.system}
    or (throw "github-copilot-cli is not packaged for ${pkgs.stdenv.hostPlatform.system}");
in
  pkgs.stdenv.mkDerivation {
    pname = "github-copilot-cli";
    inherit version;

    src = pkgs.fetchurl {
      url = "${releaseBaseUrl}/${tarball.name}.tar.gz";
      hash = tarball.hash;
    };

    nativeBuildInputs =
      [pkgs.makeBinaryWrapper]
      ++ pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [pkgs.autoPatchelfHook];
    buildInputs = pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
      pkgs.stdenv.cc.cc.lib
    ];

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;
    dontStrip = true;

    unpackPhase = ''
      tar -xzf "$src"
    '';

    installPhase = ''
      runHook preInstall
      install -Dm755 copilot "$out/libexec/copilot"
      runHook postInstall
    '';

    postInstall = ''
      makeWrapper "$out/libexec/copilot" "$out/bin/copilot" \
        --add-flags "--no-auto-update" \
        --prefix PATH : "${pkgs.lib.makeBinPath [pkgs.bash pkgs.slirp4netns pkgs.util-linux pkgs.iptables]}"
    '';

    nativeInstallCheckInputs = [pkgs.versionCheckHook];
    doInstallCheck = !pkgs.stdenv.hostPlatform.isDarwin;

    meta = with pkgs.lib; {
      description = "GitHub Copilot CLI brings the power of Copilot coding agent directly to your terminal";
      homepage = "https://github.com/github/copilot-cli";
      changelog = "https://github.com/github/copilot-cli/releases/tag/v${version}";
      license = licenses.unfree;
      mainProgram = "copilot";
      platforms = attrNames tarballs;
    };
  }
