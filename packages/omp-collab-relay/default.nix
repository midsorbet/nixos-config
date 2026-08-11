{
  bun,
  fetchurl,
  lib,
  makeWrapper,
  rcodesign,
  stdenv,
}: let
  packageJson = lib.importJSON ./package.json;
  piWireVersion = packageJson.dependencies."@oh-my-pi/pi-wire";
  piWireTarball = fetchurl {
    url = "https://registry.npmjs.org/@oh-my-pi/pi-wire/-/pi-wire-${piWireVersion}.tgz";
    hash = "sha512-LVqiDAKR0FqBRN+bRZU0lcD+vn1Q6Rv5/Ui5GCpQAI+rQPofidUZJ2VgBXF6fXSsbTmCOBmUYKmr5d3aLSEKMA==";
  };
in
  stdenv.mkDerivation {
    pname = "omp-collab-relay";
    version = piWireVersion;

    src = lib.fileset.toSource {
      root = ./.;
      fileset = lib.fileset.unions [
        ./package.json
        ./relay.test.ts
        ./relay.ts
        ./web
      ];
    };

    nativeBuildInputs = [bun makeWrapper] ++ lib.optionals stdenv.isDarwin [rcodesign];

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
        ./relay.ts \
        --outfile omp-collab-relay
      runHook postBuild
    '';

    doCheck = true;
    checkPhase = ''
      runHook preCheck
      bun test ./relay.test.ts
      runHook postCheck
    '';

    installPhase =
      ''
        runHook preInstall
        install -Dm755 omp-collab-relay "$out/libexec/omp-collab-relay"
        mkdir -p "$out/share/omp-collab-relay/web"
        cp -R web/. "$out/share/omp-collab-relay/web/"
        makeWrapper "$out/libexec/omp-collab-relay" "$out/bin/omp-collab-relay" \
          --add-flags "--web-root $out/share/omp-collab-relay/web"
        runHook postInstall
      ''
      + lib.optionalString stdenv.isDarwin ''
        rcodesign sign "$out/libexec/omp-collab-relay"
      '';

    dontStrip = true;
    dontFixup = true;

    meta = {
      description = "Hardened loopback relay for on-demand OMP collab sessions";
      homepage = "https://github.com/can1357/oh-my-pi/blob/v${piWireVersion}/docs/collab.md";
      license = lib.licenses.mit;
      mainProgram = "omp-collab-relay";
      platforms = lib.platforms.unix;
    };
  }
