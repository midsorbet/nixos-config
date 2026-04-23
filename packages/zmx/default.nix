{
  stdenvNoCC,
  fetchurl,
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
in
  stdenvNoCC.mkDerivation {
    pname = "zmx";
    inherit version;
    src = fetchurl {
      inherit (tarball) url hash;
    };
    sourceRoot = ".";
    unpackPhase = ''
      tar -xzf "$src"
    '';
    installPhase = ''
      install -Dm755 zmx "$out/bin/zmx"
    '';
  }
