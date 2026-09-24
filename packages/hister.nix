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
  version = "0.20.0";
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
      hash = "sha256-KMRTzT/jg9rJNvkUUMC9bTvklEB5ZwqmB/OOASFYRP4=";
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

  # macOS specifically needs a source build because upstream Darwin releases use
  # the netgo tag, which bypasses scoped DNS. On each Hister upgrade, check the
  # upstream GoReleaser config and return to the release binary once it stops
  # forcing netgo on Darwin.
  source = fetchFromGitHub {
    owner = "asciimoo";
    repo = "hister";
    rev = "v${version}";
    hash = "sha256-8FKieCq7T87wIawCjVoto2kX1PU2sV1LFQtz2nydzBM=";
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

    vendorHash = "sha256-piPns+kq6ZCM4Bpe7nzdjHjkZKe1VV6UY9IIMshNGpo=";
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
