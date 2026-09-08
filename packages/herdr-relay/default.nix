{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  hcloud,
  frp,
  coreutils,
  nix,
  nixos-anywhere,
  openssh,
}: let
  # Upstream puts insecure SSH defaults before user options. Remove those defaults
  # so the canonical Hooh host key remains mandatory during installation.
  strictInstaller = nixos-anywhere.overrideAttrs (old: {
    postPatch =
      (old.postPatch or "")
      + ''
        substituteInPlace src/nixos-anywhere.sh \
          --replace-fail '"-o" "UserKnownHostsFile=/dev/null" "-o" "StrictHostKeyChecking=no"' ""
      '';
  });
in
  stdenvNoCC.mkDerivation {
    pname = "herdr-relay";
    version = "1";
    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [./herdr_relay.py ./hcloud_relay.py ./relay_image.py];
    };
    nativeBuildInputs = [makeWrapper];
    dontBuild = true;
    installPhase = ''
      mkdir -p "$out/libexec/herdr-relay" "$out/bin"
      install -m 644 *.py "$out/libexec/herdr-relay/"
      makeWrapper ${python3}/bin/python3 "$out/bin/herdr-relay" \
        --add-flags "$out/libexec/herdr-relay/herdr_relay.py" \
        --prefix PATH : "${lib.makeBinPath [hcloud frp coreutils nix strictInstaller openssh]}"
    '';
    meta = {
      description = "Native-tool orchestration for the ephemeral Hooh frp relay";
      mainProgram = "herdr-relay";
      platforms = lib.platforms.unix;
    };
  }
