{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.wslDev;
  sharedPackages = import ../shared/packages.nix {inherit pkgs;};

  windowsClipboard = pkgs.symlinkJoin {
    name = "windows-clipboard";
    paths = [
      (pkgs.writeShellScriptBin "pbcopy" ''
        exec pwsh.exe -NoProfile -Command '$text = [Console]::In.ReadToEnd(); Set-Clipboard -Value $text'
      '')
      (pkgs.writeShellScriptBin "pbpaste" ''
        exec pwsh.exe -NoProfile -Command '[Console]::Out.Write((Get-Clipboard -Raw).Replace("`r", ""))'
      '')
    ];
  };
in {
  imports = [
    ../shared
  ];

  options.local.wslDev = {
    enable = lib.mkEnableOption "shared NixOS-WSL developer environment";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "Default WSL user for this distribution.";
    };

    flakePath = lib.mkOption {
      type = lib.types.str;
      default = "/home/${cfg.user}/.config/nixos-config";
      description = "Path used by nh and NH_FLAKE on this WSL host.";
    };

    enableSshServer = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this WSL distribution should accept inbound SSH.";
    };

    authorizedKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Public SSH keys allowed for the default WSL user.";
    };
  };

  config = lib.mkIf cfg.enable {
    wsl = {
      enable = true;
      defaultUser = cfg.user;
      ssh-agent.enable = true;
      useWindowsDriver = true;
      wslConf.interop.appendWindowsPath = false;
    };

    users.users.${cfg.user} = {
      shell = pkgs.wrapperPackages.zsh;
      openssh.authorizedKeys.keys = cfg.authorizedKeys;
    };

    nix = {
      package = pkgs.nix;
      settings = {
        experimental-features = ["nix-command" "flakes"];
        trusted-users = ["@wheel" cfg.user];
        substituters = ["https://nix-community.cachix.org" "https://cache.nixos.org"];
        trusted-public-keys = [
          "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      };
    };

    environment = {
      systemPackages =
        sharedPackages
        ++ (with pkgs; [
          awscli2
          file
          gh
          github-copilot-cli
          git-filter-repo
          p7zip
          podman
          ripgrep-all
          rsync
          uv
          which
          windowsClipboard
          xz
        ]);

      variables = {
        BROWSER = "/mnt/c/Windows/explorer.exe";
        NH_FLAKE = cfg.flakePath;
      };

      etc."containers/containers.conf".text = ''
        [engine]
        active_service = "podman-machine-default"
        remote = true

        [engine.service_destinations.podman-machine-default]
        uri = "unix:///mnt/wsl/podman-sockets/podman-machine-default/podman-user.sock"

        [engine.service_destinations.podman-machine-default-root]
        uri = "unix:///mnt/wsl/podman-sockets/podman-machine-default/podman-root.sock"
      '';
    };

    fonts.packages = with pkgs; [
      maple-mono.NF
      nerd-fonts.symbols-only
    ];

    programs = {
      nix-ld.enable = true;
      nh = {
        enable = true;
        clean = {
          enable = true;
          extraArgs = "--keep-since 4d --keep 3";
        };
        flake = cfg.flakePath;
      };

      ssh = {
        knownHosts.github = {
          hostNames = ["github.com"];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl";
        };
        extraConfig = ''
          Host *
            SendEnv LANG LC_*
            HashKnownHosts yes
            ServerAliveInterval 30
            ServerAliveCountMax 6
            TCPKeepAlive yes

          Host github.com
            IdentitiesOnly yes
            IdentityFile /home/${cfg.user}/.ssh/id_github
        '';
      };
    };

    services.openssh = lib.mkIf cfg.enableSshServer {
      enable = true;
      openFirewall = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
        PermitRootLogin = "no";
        AllowUsers = [cfg.user];
      };
    };
  };
}
