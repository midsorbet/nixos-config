{
  config,
  lib,
  pkgs,
  ...
}: let
  user = config.system.primaryUser;
  home = config.system.primaryUserHome;
  version = "0.1.0";
  package = pkgs.stdenvNoCC.mkDerivation {
    pname = "kittylitter";
    inherit version;

    src = pkgs.fetchurl {
      url = "https://github.com/dnakov/litter/releases/download/v${version}/kittylitter-aarch64-apple-darwin.tar.xz";
      hash = "sha256-z+Kn/A9taMIYPDnKnUnZ5a8e9e7V2F+MzUCjnaqOJNU=";
    };

    sourceRoot = "kittylitter-aarch64-apple-darwin";
    dontStrip = true;

    installPhase = ''
      runHook preInstall

      install -Dm755 kittylitter "$out/bin/kittylitter"
      install -Dm644 README.md "$out/share/doc/kittylitter/README.md"
      install -Dm644 LICENSE "$out/share/licenses/kittylitter/LICENSE"

      runHook postInstall
    '';

    meta = {
      description = "Iroh-backed daemon that multiplexes local coding agents for paired clients";
      homepage = "https://github.com/dnakov/litter";
      license = lib.licenses.gpl3Only;
      mainProgram = "kittylitter";
      platforms = ["aarch64-darwin"];
      sourceProvenance = [lib.sourceTypes.binaryNativeCode];
    };
  };
  logDir = "${home}/Library/Logs/com.sigkitten.kittylitter";
  path = lib.concatStringsSep ":" [
    "${package}/bin"
    "/etc/profiles/per-user/${user}/bin"
    "/run/current-system/sw/bin"
    "${home}/.nix-profile/bin"
    "/nix/var/nix/profiles/default/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
    "/Applications/Codex.app/Contents/Resources"
  ];
in {
  hjem.users.${user} = {
    inherit user;
    directory = home;
    packages = [package];
    files = {
      "Library/Application Support/com.sigkitten.kittylitter" = {
        type = "directory";
        permissions = "700";
      };

      "Library/Logs/com.sigkitten.kittylitter" = {
        type = "directory";
        permissions = "700";
      };
    };
  };

  launchd.user.agents.kittylitter = {
    environment = {
      HOME = home;
      PATH = path;
    };
    serviceConfig = {
      Label = "com.sigkitten.kittylitter";
      ProgramArguments = [
        "${package}/bin/kittylitter"
        "serve"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "${logDir}/daemon.log";
      StandardErrorPath = "${logDir}/daemon.log";
    };
  };
}
