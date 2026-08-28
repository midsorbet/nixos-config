{pkgs}: let
  inherit (pkgs) lib stdenvNoCC;
  version = "0.5.15";

  seedsCliSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/@os-eco/seeds-cli/-/seeds-cli-${version}.tgz";
    hash = "sha512-0DD6xYWpJYU9FeglT0X/J+6pf+NJIdPuFj4vM3haN1yZ2gqfxbpLoob4/FjzdFauuSbkmDT/A/3xGj1tHUXmHQ==";
  };
  ajvSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/ajv/-/ajv-8.20.0.tgz";
    hash = "sha512-Thbli+OlOj+iMPYFBVBfJ3OmCAnaSyNn4M1vz9T6Gka5Jt9ba/HIR56joy65tY6kx/FCF5VXNB819Y7/GUrBGA==";
  };
  chalkSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/chalk/-/chalk-5.6.2.tgz";
    hash = "sha512-7NzBL0rN6fMUW+f7A6Io4h40qQlG+xGmtMxfbnH/K7TAtt8JQWVQK+6g0UXKMeVJoyV5EkkNsErQ8pVD3bLHbA==";
  };
  commanderSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/commander/-/commander-14.0.3.tgz";
    hash = "sha512-H+y0Jo/T1RZ9qPP4Eh1pkcQcLRglraJaSLoyOtHxu6AapkjWVCy2Sit1QQ4x3Dng8qDlSsZEet7g5Pq06MvTgw==";
  };
  fastDeepEqualSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/fast-deep-equal/-/fast-deep-equal-3.1.3.tgz";
    hash = "sha512-f3qQ9oQy9j2AhBe/H9VC91wLmKBCCU/gDOnKNAYG5hswO7BLKj09Hc5HYNz9cGI++xlpDCIgDaitVs03ATR84Q==";
  };
  fastUriSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/fast-uri/-/fast-uri-3.1.2.tgz";
    hash = "sha512-rVjf7ArG3LTk+FS6Yw81V1DLuZl1bRbNrev6Tmd/9RaroeeRRJhAt7jg/6YFxbvAQXUCavSoZhPPj6oOx+5KjQ==";
  };
  jsonSchemaTraverseSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/json-schema-traverse/-/json-schema-traverse-1.0.0.tgz";
    hash = "sha512-NM8/P9n3XjXhIZn1lLhkFaACTOURQXjWhV4BA/RnOv8xvgqtqpAX9IO4mRQxSx1Rlo4tqzeqb0sOlruaOy3dug==";
  };
  requireFromStringSource = pkgs.fetchurl {
    url = "https://registry.npmjs.org/require-from-string/-/require-from-string-2.0.2.tgz";
    hash = "sha512-Xf0nWe6RseziFMu+Ap9biiUbmplq6S9/p+7w7YXP/JBHhrUDDUhwa+vANyubuqfZWTveU//DYVGsDG7RKL/vEw==";
  };
in
  stdenvNoCC.mkDerivation {
    pname = "seeds-cli";
    inherit version;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    nativeBuildInputs = [pkgs.makeWrapper];

    installPhase = ''
      runHook preInstall

      installNpmPackage() {
        local source="$1"
        local destination="$2"
        mkdir -p "$destination"
        tar -xzf "$source" --strip-components=1 -C "$destination"
      }

      installNpmPackage ${seedsCliSource} "$out/libexec/seeds-cli"
      installNpmPackage ${ajvSource} "$out/libexec/seeds-cli/node_modules/ajv"
      installNpmPackage ${chalkSource} "$out/libexec/seeds-cli/node_modules/chalk"
      installNpmPackage ${commanderSource} "$out/libexec/seeds-cli/node_modules/commander"
      installNpmPackage ${fastDeepEqualSource} "$out/libexec/seeds-cli/node_modules/fast-deep-equal"
      installNpmPackage ${fastUriSource} "$out/libexec/seeds-cli/node_modules/fast-uri"
      installNpmPackage ${jsonSchemaTraverseSource} "$out/libexec/seeds-cli/node_modules/json-schema-traverse"
      installNpmPackage ${requireFromStringSource} "$out/libexec/seeds-cli/node_modules/require-from-string"

      mkdir -p "$out/bin"
      makeWrapper ${pkgs.bun}/bin/bun "$out/bin/sd" \
        --add-flags "run $out/libexec/seeds-cli/src/index.ts"

      runHook postInstall
    '';

    nativeInstallCheckInputs = [pkgs.versionCheckHook];
    doInstallCheck = true;
    versionCheckProgramArg = "--version";

    meta = {
      description = "Git-native issue tracking for humans and coding agents";
      homepage = "https://github.com/jayminwest/seeds";
      changelog = "https://github.com/jayminwest/seeds/releases/tag/v${version}";
      license = lib.licenses.mit;
      mainProgram = "sd";
      platforms = lib.platforms.darwin;
    };
  }
