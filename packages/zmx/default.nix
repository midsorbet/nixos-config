{}: final: prev: let
  system = prev.stdenvNoCC.hostPlatform.system;
  version = "0.6.0";
  zmxMeta = {
    description = "Session persistence for terminal processes";
    longDescription = ''
      zmx keeps terminal shell sessions alive across disconnects. It supports
      attaching and detaching without killing the process, native terminal
      scrollback, multiple clients, sending commands to sessions, and printing
      scrollback history as plain text. It intentionally does not provide
      windows, tabs, or splits.
    '';
    homepage = "https://zmx.sh/";
    changelog = "https://github.com/neurosnap/zmx/blob/v${version}/CHANGELOG.md";
    downloadPage = "https://zmx.sh/#install";
    license = prev.lib.licenses.mit;
    mainProgram = "zmx";
    platforms = ["aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux"];
  };
  tarballs = {
    "aarch64-darwin" = {
      name = "zmx-${version}-macos-aarch64.tar.gz";
      hash = "sha256-PwcMbjjLOkjdwTHb6Vb9TE6/TKbPzFfDrLtAmU8Wl4c=";
    };
    "x86_64-darwin" = {
      name = "zmx-${version}-macos-x86_64.tar.gz";
      hash = "sha256-Hmo+VkC4UzL6yViqSx/HY5C8H2mLa0l1RZ2J87z7GGU=";
    };
    "aarch64-linux" = {
      name = "zmx-${version}-linux-aarch64.tar.gz";
      hash = "sha256-wj9LTKgOFE4ynQQrkarkhZ0jIXqwcHazg69BNNl/qsU=";
    };
    "x86_64-linux" = {
      name = "zmx-${version}-linux-x86_64.tar.gz";
      hash = "sha256-MJ2RO5gq4W6sKoVPQR3kDszAtkr+2JKqAqC+NR8CccE=";
    };
  };
  tarball =
    tarballs.${system}
    or (throw "zmx is not packaged for ${system}");
  zmx = prev.stdenvNoCC.mkDerivation {
    pname = "zmx";
    inherit version;

    src = prev.fetchurl {
      url = "https://github.com/neurosnap/zmx/releases/download/v${version}/${tarball.name}";
      hash = tarball.hash;
    };

    sourceRoot = ".";

    unpackPhase = ''
      tar -xzf "$src"
    '';

    installPhase = ''
      install -Dm755 zmx "$out/bin/zmx"
    '';

    meta = zmxMeta;
  };
in {
  inherit zmx;

  zmx-select = prev.symlinkJoin rec {
    name = "zmx-select";
    paths = [
      ((prev.writeScriptBin "zmx-select" (builtins.readFile ./zmx-select.sh)).overrideAttrs (old: {
        buildCommand = ''
          ${old.buildCommand}
          patchShebangs $out
        '';
      }))
      zmx
      prev.fzf
      prev.gawk
      prev.gnused
    ];
    nativeBuildInputs = [prev.makeWrapper];
    postBuild = "wrapProgram $out/bin/${name} --prefix PATH : $out/bin";
  };
}
