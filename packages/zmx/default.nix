{
  stdenvNoCC,
  fetchurl,
}: let
  version = "0.3.0";
  tarballs = {
    "aarch64-darwin" = {
      url = "https://zmx.sh/a/zmx-${version}-macos-aarch64.tar.gz";
      hash = "sha256-yjgZvb47NA/XG+u7UFpSk9gjzOIqmYa0qIChLRX9m/k=";
    };
    "aarch64-linux" = {
      url = "https://zmx.sh/a/zmx-${version}-linux-aarch64.tar.gz";
      hash = "sha256-OTMWzGzOjPZGdr4hj3TTNqbG2OcRc0Ifd0QLaAoRlLQ=";
    };
    "x86_64-linux" = {
      url = "https://zmx.sh/a/zmx-${version}-linux-x86_64.tar.gz";
      hash = "sha256-/K/xWB61pqPll4Gq13qMoGm0Q1vC/sQT3TI7RaTf3zI=";
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
