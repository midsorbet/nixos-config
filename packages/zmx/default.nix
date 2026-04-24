{
  stdenvNoCC,
  fetchurl,
  fzf,
  gawk,
  lib,
  makeWrapper,
  writeScriptBin,
}: let
  version = "0.5.0";
  tarballs = {
    "aarch64-darwin" = {
      url = "https://zmx.sh/a/zmx-${version}-macos-aarch64.tar.gz";
      hash = "sha256-O5N58P8M8Qf3+HBI0sRfb76r7ViNZ2rYasIYvtko0Qc=";
    };
    "aarch64-linux" = {
      url = "https://zmx.sh/a/zmx-${version}-linux-aarch64.tar.gz";
      hash = "sha256-OTMWzGzOjPZGdr4hj3TTNqbG2OcRc0Ifd0QLaAoRlLQ=";
    };
    "x86_64-linux" = {
      url = "https://zmx.sh/a/zmx-${version}-linux-x86_64.tar.gz";
      hash = "sha256-TMH2uFTczcq65MuRvQN5oj5vghAEivXYHgZh5ZSlDCg=";
    };
  };
  tarball = tarballs.${stdenvNoCC.hostPlatform.system};
  zmxSelect = (writeScriptBin "zmx-select" (builtins.readFile ./zmx-select.sh)).overrideAttrs (old: {
    buildCommand = ''
      ${old.buildCommand}
      patchShebangs $out
    '';
  });
in
  stdenvNoCC.mkDerivation {
    pname = "zmx";
    inherit version;
    src = fetchurl {
      inherit (tarball) url hash;
    };
    sourceRoot = ".";
    nativeBuildInputs = [makeWrapper];
    unpackPhase = ''
      tar -xzf "$src"
    '';
    installPhase = ''
      install -Dm755 zmx "$out/bin/zmx"
      makeWrapper ${zmxSelect}/bin/zmx-select "$out/bin/zmx-select" \
        --prefix PATH : "$out/bin:${lib.makeBinPath [fzf gawk]}"
    '';
    meta.mainProgram = "zmx";
  }
