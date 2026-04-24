{
  lib,
  mdfriedInput,
  stdenv,
}: let
  mdfried = mdfriedInput.packages."${stdenv.hostPlatform.system}".default;
in
  mdfried.overrideAttrs (_:
    lib.optionalAttrs stdenv.hostPlatform.isDarwin {
      doCheck = false;
    })
