{pkgs}:
pkgs.stdenv.mkDerivation {
  pname = "codex";
  version = "0.144.1";

  src = pkgs.fetchurl {
    url = "https://github.com/openai/codex/releases/download/rust-v0.144.1/codex-x86_64-unknown-linux-musl.tar.gz";
    hash = "sha256-hAka4gxl/MfUEg25fRvVfX/435x2Cft4HHjC671PWig=";
  };

  sourceRoot = ".";
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  nativeBuildInputs = [
    pkgs.installShellFiles
    pkgs.makeWrapper
  ];

  installPhase = ''
    runHook preInstall
    install -Dm755 codex-x86_64-unknown-linux-musl "$out/libexec/codex"
    makeWrapper "$out/libexec/codex" "$out/bin/codex" \
      --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.ripgrep pkgs.bubblewrap]}
    runHook postInstall
  '';

  postInstall = ''
    installShellCompletion --cmd codex \
      --bash <("$out/bin/codex" completion bash) \
      --fish <("$out/bin/codex" completion fish) \
      --zsh <("$out/bin/codex" completion zsh)
  '';

  nativeInstallCheckInputs = [pkgs.versionCheckHook];
  doInstallCheck = true;
  versionCheckProgramArg = "--version";

  meta = {
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    changelog = "https://github.com/openai/codex/releases/tag/rust-v0.144.1";
    license = pkgs.lib.licenses.asl20;
    mainProgram = "codex";
    platforms = ["x86_64-linux"];
    sourceProvenance = [pkgs.lib.sourceTypes.binaryNativeCode];
  };
}
