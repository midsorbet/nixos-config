{pkgs}: let
  inherit (pkgs) lib;
  packageJson = lib.importJSON ./package.json;
  # Version-locked to the managed OMP release line; the npm package publishes
  # in lockstep with oh-my-pi releases. Bump together with packages/omp.nix
  # and keep bun.lock in sync (`bun install --save-text-lockfile`).
  piWireVersion = packageJson.dependencies."@oh-my-pi/pi-wire";

  piWireTarball = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@oh-my-pi/pi-wire/-/pi-wire-${piWireVersion}.tgz";
    hash = "sha512-0fAaouJtptY4nqsa7fvuAvFI5fd8o267yX4sFcb24fcMkf/7ziqRC9h4a/tV7COmMFRtg2Ykoks4u97sw0lblQ==";
  };

  # Bun-compiled standalone binary, following modem-dev/hunk's nix/package.nix:
  # deps staged by Nix (no network install), `bun build --compile`, no
  # fixup/strip (both corrupt the embedded blob), then ad-hoc re-sign on
  # Darwin. Bun 1.3.13's compile output carries a self-inconsistent
  # linker signature (strict verify fails, the binary dies with SIGKILL /
  # Code Signature Invalid — same class as the repo's hunk override), and
  # /usr/bin/codesign refuses to replace it; rcodesign rewrites it cleanly.
  unwrapped = pkgs.stdenv.mkDerivation {
    pname = "omp-collab-tunnel-unwrapped";
    version = piWireVersion;

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [./relay.ts ./tunnel.ts ./package.json];
    };

    nativeBuildInputs = [pkgs.bun] ++ lib.optionals pkgs.stdenv.isDarwin [pkgs.rcodesign];

    configurePhase = ''
      runHook preConfigure
      mkdir -p node_modules/@oh-my-pi/pi-wire
      tar -xzf ${piWireTarball} -C node_modules/@oh-my-pi/pi-wire --strip-components=1
      runHook postConfigure
    '';

    buildPhase = ''
      runHook preBuild
      mkdir -p .bun-tmp .bun-install
      BUN_TMPDIR=$PWD/.bun-tmp \
      BUN_INSTALL=$PWD/.bun-install \
      bun build --compile \
        --no-compile-autoload-bunfig \
        ./tunnel.ts \
        --outfile omp-collab-tunnel
      runHook postBuild
    '';

    installPhase =
      ''
        runHook preInstall
        install -Dm755 omp-collab-tunnel "$out/bin/omp-collab-tunnel"
        runHook postInstall
      ''
      + lib.optionalString pkgs.stdenv.isDarwin ''
        rcodesign sign "$out/bin/omp-collab-tunnel"
      '';

    dontStrip = true;
    dontFixup = true;

    meta = {
      description = "OMP collab relay plus Cloudflare Quick Tunnel launcher";
      mainProgram = "omp-collab-tunnel";
    };
  };
in {
  # Wrapper pins the Nix cloudflared for the compiled binary; same
  # runCommand + makeWrapper shape as modules/omp's wrapped package.
  omp-collab-tunnel =
    pkgs.runCommand "omp-collab-tunnel-${piWireVersion}" {
      nativeBuildInputs = [pkgs.makeWrapper];
      meta = {
        description = "On-demand OMP collab relay behind a temporary Cloudflare Quick Tunnel";
        mainProgram = "omp-collab-tunnel";
      };
    } ''
      mkdir -p "$out/bin"
      makeWrapper ${unwrapped}/bin/omp-collab-tunnel "$out/bin/omp-collab-tunnel" \
        --set-default OMP_COLLAB_CLOUDFLARED ${pkgs.cloudflared}/bin/cloudflared
    '';
}
