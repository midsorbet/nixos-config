{
  buildGoModule,
  buildNpmPackage,
  fetchFromGitHub,
  fetchurl,
  importNpmLock,
  lib,
  pkg-config,
  sqlite,
  stdenv,
  versionCheckHook,
}: let
  version = "0.19.0";
  platforms = [
    "aarch64-darwin"
    "x86_64-linux"
  ];
  meta = {
    description = "Private full-text search engine for visited pages and local files";
    homepage = "https://hister.org";
    changelog = "https://github.com/asciimoo/hister/releases/tag/v${version}";
    license = lib.licenses.agpl3Plus;
    mainProgram = "hister";
    inherit platforms;
  };

  linuxBinary = stdenv.mkDerivation {
    pname = "hister";
    inherit version meta;

    src = fetchurl {
      url = "https://github.com/asciimoo/hister/releases/download/v${version}/hister_${version}_linux_amd64";
      hash = "sha256-dXH3uUA5kX1Rk3L6av8Y/hLC71D5gayEfsGv9NfkFwE=";
    };

    dontUnpack = true;
    dontStrip = true;

    installPhase = ''
      runHook preInstall
      install -Dm755 "$src" "$out/bin/hister"
      runHook postInstall
    '';

    nativeInstallCheckInputs = [versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";
  };

  # Upstream Darwin releases use the netgo tag, which bypasses macOS scoped DNS.
  # Build from source so Hister uses the native resolver for private split DNS.
  source = fetchFromGitHub {
    owner = "asciimoo";
    repo = "hister";
    rev = "v${version}";
    hash = "sha256-0DNrO8wLgkVKTNWfSjkVpwUBn0+X7xb2pb7mXnD1SIU=";
  };

  frontend = buildNpmPackage {
    pname = "hister-frontend";
    inherit version;
    src = source;
    npmWorkspace = "webui/app";
    npmDeps = importNpmLock {npmRoot = source;};
    npmConfigHook = importNpmLock.npmConfigHook;
    dontNpmBuild = false;

    preBuild = ''
      patchShebangs webui
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p "$out"
      cp -r webui/app/build/* "$out/"
      runHook postInstall
    '';
  };

  darwinSource = buildGoModule {
    pname = "hister";
    inherit version meta;
    src = source;

    vendorHash = "sha256-5weBvVQotKuVaBPqaBWzsK571EDPTnAKpim4i6fpeg0=";
    proxyVendor = true;

    nativeBuildInputs = [pkg-config];
    buildInputs = [sqlite];
    tags = ["libsqlite3"];

    preBuild = ''
      mkdir -p server/static/app
      cp -r ${frontend}/* server/static/app/
    '';

    ldflags = [
      "-s"
      "-w"
      "-X main.version=${version}"
      "-X main.commit=v${version}"
    ];

    subPackages = ["."];
    nativeInstallCheckInputs = [versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";

    passthru = {inherit frontend;};
  };
in
  if stdenv.hostPlatform.system == "aarch64-darwin"
  then darwinSource
  else if stdenv.hostPlatform.system == "x86_64-linux"
  then linuxBinary
  else throw "Hister is not packaged for ${stdenv.hostPlatform.system}"
