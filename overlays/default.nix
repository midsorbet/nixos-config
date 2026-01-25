{...}: {
  nixpkgs.overlays = [
    (final: prev: let
      zmxVersion = "0.2.0";
      tarball =
        if prev.stdenv.isDarwin
        then {
          url = "https://zmx.sh/a/zmx-${zmxVersion}-macos-aarch64.tar.gz";
          hash = "sha256-nGjCLm4hZ3p4a/4LJJuyTc11uqXWgXBQqM+/4HxAh7Q=";
        }
        else {
          url = "https://zmx.sh/a/zmx-${zmxVersion}-linux-aarch64.tar.gz";
          hash = "sha256-IhEP7/Wl4/HET0xVsr6u+PUgC/q8TZRqncg2vCEOEec=";
        };
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
