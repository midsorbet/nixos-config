{
  fetchurl,
  lib,
  stdenv,
  version ? "0.24.0",
  hash ? "688c91e2f9b195869b2db27f1e37512a01cb403426f3314324b5d6cdd7f7bfd1",
}:
stdenv.mkDerivation {
  pname = "cua-driver";
  inherit version;

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-driver-rs-v${version}/cua-driver-rs-${version}-darwin-universal.tar.gz";
    sha256 = hash;
  };

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/Applications" "$out/bin"
    cp -R CuaDriver.app "$out/Applications/CuaDriver.app"
    ln -s "$out/Applications/CuaDriver.app/Contents/MacOS/cua-driver" "$out/bin/cua-driver"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    app="$out/Applications/CuaDriver.app"
    test -x "$app/Contents/MacOS/cua-driver"
    grep -A 1 '<key>CFBundleIdentifier</key>' "$app/Contents/Info.plist" \
      | grep -q '<string>com.trycua.driver</string>'
    grep -A 1 '<key>CFBundleExecutable</key>' "$app/Contents/Info.plist" \
      | grep -q '<string>cua-driver</string>'
    runHook postInstallCheck
  '';

  meta = with lib; {
    description = "Native macOS MCP server for computer use";
    homepage = "https://github.com/trycua/cua";
    changelog = "https://github.com/trycua/cua/releases/tag/cua-driver-rs-v${version}";
    license = licenses.mit;
    mainProgram = "cua-driver";
    platforms = platforms.darwin;
    sourceProvenance = [sourceTypes.binaryNativeCode];
  };
}
