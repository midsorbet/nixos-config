{inputs}: final: prev: let
  system = prev.stdenvNoCC.hostPlatform.system;
  version = "0.5.0";
  tarballs = {
    "aarch64-darwin" = {
      url = "https://zmx.sh/a/zmx-${version}-macos-aarch64.tar.gz";
      hash = "sha256-O5N58P8M8Qf3+HBI0sRfb76r7ViNZ2rYasIYvtko0Qc=";
    };
  };
  zmx-tarball = prev.stdenvNoCC.mkDerivation {
    pname = "zmx";
    inherit version;

    src = prev.fetchurl tarballs.${system};

    sourceRoot = ".";

    unpackPhase = ''
      tar -xzf "$src"
    '';

    installPhase = ''
      install -Dm755 zmx "$out/bin/zmx"
    '';

    meta = {
      homepage = "https://zmx.sh/";
      changelog = "https://github.com/neurosnap/zmx/blob/v${version}/CHANGELOG.md";
      mainProgram = "zmx";
      platforms = builtins.attrNames tarballs;
    };
  };
  zmx =
    if builtins.hasAttr system tarballs
    then zmx-tarball
    else inputs.zmx.packages.${system}.zmx;
  zmx-select-script = (prev.writeScriptBin "zmx-select" (builtins.readFile ./zmx-select.sh)).overrideAttrs (old: {
    buildCommand = ''
      ${old.buildCommand}
      patchShebangs $out
    '';
  });
in {
  inherit zmx;

  zmx-select = prev.symlinkJoin rec {
    name = "zmx-select";
    paths = [zmx-select-script zmx prev.fzf prev.gawk prev.gnused];
    nativeBuildInputs = [prev.makeWrapper];
    postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
  };
}
