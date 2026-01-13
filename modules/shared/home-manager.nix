{
  config,
  pkgs,
  lib,
  ...
}: let
  user = "me";
  localSecrets = import ../../secrets.local.nix;
in {
  bat = {
    enable = true;
  };

  direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  fd = {
    enable = true;
  };

  fzf = {
    enable = true;
  };

  jq = {
    enable = true;
  };

  git = {
    enable = true;
    settings = {
      user = {
        name = localSecrets.name;
        email = localSecrets.email;
        init.defaultBranch = "main";
        core = {
          editor = "vim";
          autocrlf = "input";
        };
      };
    };
  };

  pandoc.enable = true;

  ripgrep = {
    enable = true;
  };

  ssh = {
    enable = true;
    enableDefaultConfig = false;
    includes = [
      (
        lib.mkIf pkgs.stdenv.hostPlatform.isLinux
        "/home/${user}/.ssh/config_external"
      )
      (
        lib.mkIf pkgs.stdenv.hostPlatform.isDarwin
        "/Users/${user}/.ssh/config_external"
      )
    ];
    matchBlocks = {
      "*" = {
        # Set the default values we want to keep
        sendEnv = ["LANG" "LC_*"];
        hashKnownHosts = true;
      };
      "github.com" = {
        identitiesOnly = true;
        identityFile = [
          (
            lib.mkIf pkgs.stdenv.hostPlatform.isLinux
            "/home/${user}/.ssh/id_github"
          )
          (
            lib.mkIf pkgs.stdenv.hostPlatform.isDarwin
            "/Users/${user}/.ssh/id_github"
          )
        ];
      };
    };
  };

  zellij = {
    enable = true;
    enableZshIntegration = true;
    attachExisitingSession = true;
    settings = {
      session_serialization = true;
      pane_viewport_serialization = true;
      scrollback_lines_to_serialize = 1000;
    };
  };

  # Shared shell configuration
  zsh = {
    enable = true;
    cdpath = ["~/Projects"];
    initContent = lib.mkBefore ''
      if [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
        . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        . /nix/var/nix/profiles/default/etc/profile.d/nix.sh
      fi
    '';
  };
}
