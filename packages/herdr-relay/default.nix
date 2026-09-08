{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  cloudflared,
  coreutils,
}:
stdenvNoCC.mkDerivation {
  pname = "herdr-relay";
  version = "1";
  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [./herdr_relay.py];
  };
  nativeBuildInputs = [makeWrapper];
  dontBuild = true;
  installPhase = ''
    mkdir -p "$out/libexec/herdr-relay" "$out/bin"
    install -m 644 herdr_relay.py "$out/libexec/herdr-relay/herdr_relay.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/herdr-relay" \
      --add-flags "$out/libexec/herdr-relay/herdr_relay.py" \
      --prefix PATH : "${lib.makeBinPath [cloudflared coreutils]}"
  '';
  meta = {
    description = "On-demand Cloudflare Tunnel connector lifecycle";
    mainProgram = "herdr-relay";
    platforms = lib.platforms.unix;
  };
}
