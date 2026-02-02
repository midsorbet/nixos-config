{...}: {
  nixpkgs.overlays = [
    (final: prev: let
      zmxVersion = "0.3.0";
      tarballs = {
        "aarch64-darwin" = {
          url = "https://zmx.sh/a/zmx-${zmxVersion}-macos-aarch64.tar.gz";
          hash = "sha256-yjgZvb47NA/XG+u7UFpSk9gjzOIqmYa0qIChLRX9m/k=";
        };
        "aarch64-linux" = {
          url = "https://zmx.sh/a/zmx-${zmxVersion}-linux-aarch64.tar.gz";
          hash = "sha256-OTMWzGzOjPZGdr4hj3TTNqbG2OcRc0Ifd0QLaAoRlLQ=";
        };
        "x86_64-linux" = {
          url = "https://zmx.sh/a/zmx-${zmxVersion}-linux-x86_64.tar.gz";
          hash = "sha256-/K/xWB61pqPll4Gq13qMoGm0Q1vC/sQT3TI7RaTf3zI=";
        };
      };
      tarball = tarballs.${prev.stdenv.hostPlatform.system};
      zmxFromTarball = prev.stdenvNoCC.mkDerivation {
        pname = "zmx";
        version = zmxVersion;
        src = prev.fetchurl {
          inherit (tarball) url hash;
        };
        sourceRoot = ".";
        unpackPhase = ''
          tar -xzf "$src"
        '';
        installPhase = ''
          install -Dm755 zmx "$out/bin/zmx"
        '';
      };
    in {
      zmx = zmxFromTarball;
    })
  ];
}
