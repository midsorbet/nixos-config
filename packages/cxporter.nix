{
  fetchFromGitHub,
  fetchurl,
  lib,
  openssl,
  pkg-config,
  rustPlatform,
}: let
  librustyV8 = fetchurl {
    url = "https://github.com/denoland/rusty_v8/releases/download/v150.4.0/librusty_v8_release_aarch64-apple-darwin.a.gz";
    hash = "sha256-zNj4FIW4IsWxiuun+d65KaM4LYasZzu/DzZvBod+axA=";
  };
in
  rustPlatform.buildRustPackage rec {
    pname = "cxporter";
    version = "0.1.0-unstable-2026-07-29";

    src = fetchFromGitHub {
      owner = "mkusaka";
      repo = "cxporter";
      rev = "7e04928523de20337d9868f708c4da7c7a2ebb5f";
      hash = "sha256-qGQpEHMJCbslI4rUWBzoivJgsBdnbLw59RaNEPilibk=";
    };

    cargoHash = "sha256-4Vt7fP4tPMadMuSFpdjesSuCo41v6CgljN0K1rc2V2c=";
    env.RUSTY_V8_ARCHIVE = librustyV8;

    nativeBuildInputs = [pkg-config];
    buildInputs = [openssl];

    meta = {
      description = "Direct CLI access to Codex-authenticated MCP servers";
      homepage = "https://github.com/mkusaka/cxporter";
      license = lib.licenses.mit;
      mainProgram = "cxporter";
      platforms = ["aarch64-darwin"];
    };
  }
