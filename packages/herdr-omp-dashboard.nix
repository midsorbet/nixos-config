{
  lib,
  ompPackage,
  stdenvNoCC,
  vaultRoot,
}:
stdenvNoCC.mkDerivation {
  pname = "herdr-omp-dashboard-plugin";
  version = "0.1.0";
  src = ./herdr-omp-dashboard;

  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    substitute herdr-plugin.toml "$out/herdr-plugin.toml" \
      --replace-fail '@ompCommand@' '${lib.getExe ompPackage}' \
      --replace-fail '@vaultRoot@' '${vaultRoot}'
    runHook postInstall
  '';

  meta = {
    description = "Herdr plugin for launching OMP agents and opening the dashboard";
    license = lib.licenses.mit;
    platforms = lib.platforms.darwin;
  };
}
