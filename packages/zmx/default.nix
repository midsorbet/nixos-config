{inputs}: final: prev: let
  system = prev.stdenvNoCC.hostPlatform.system;
  version = "0.5.0";
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
    platforms = ["aarch64-darwin" "x86_64-linux" "aarch64-linux"];
  };
  tarballs = {
    "aarch64-darwin" = {
      url = "https://zmx.sh/a/zmx-${version}-macos-aarch64.tar.gz";
      hash = "sha256-O5N58P8M8Qf3+HBI0sRfb76r7ViNZ2rYasIYvtko0Qc=";
    };
  };
  zmx =
    if builtins.hasAttr system tarballs
    then
      prev.stdenvNoCC.mkDerivation {
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

        meta = zmxMeta;
      }
    else
      inputs.zmx.packages.${system}.zmx.overrideAttrs (old: {
        meta = (old.meta or {}) // zmxMeta;
      });
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
