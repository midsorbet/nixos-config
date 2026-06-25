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

  remoteUxTools = let
    oscCopy = pkgs.writeShellApplication {
      name = "osc-copy";
      runtimeInputs = [pkgs.coreutils];
      text = ''
        payload="$(
          if [ "$#" -gt 0 ]; then
            printf '%s' "$*"
          else
            cat
          fi | base64 --wrap=0
        )"

        printf '\033]52;c;%s\a' "$payload"
      '';
    };

    nvimOsc52 = pkgs.writeShellApplication {
      name = "nvim-osc52";
      runtimeInputs = [pkgs.neovim];
      text = ''
        exec nvim --cmd "lua vim.g.clipboard = 'osc52'; vim.opt.clipboard:append('unnamedplus')" "$@"
      '';
    };

    pget = pkgs.writeShellApplication {
      name = "pget";
      runtimeInputs = [pkgs.trzsz-go];
      text = ''
        if [ "$#" -eq 0 ]; then
          echo "usage: pget FILE..." >&2
          exit 2
        fi

        exec tsz -d "$@"
      '';
    };

    pput = pkgs.writeShellApplication {
      name = "pput";
      runtimeInputs = [pkgs.trzsz-go];
      text = ''
        exec trz "$@"
      '';
    };

    pserve = pkgs.writeShellApplication {
      name = "pserve";
      runtimeInputs = [pkgs.miniserve];
      text = ''
        path="''${1:-.}"
        port="''${2:-8765}"

        echo "Forward with: ssh -N -L 127.0.0.1:$port:127.0.0.1:$port porygon" >&2
        exec miniserve --interfaces 127.0.0.1 --port "$port" "$path"
      '';
    };

    pview = pkgs.writeShellApplication {
      name = "pview";
      runtimeInputs = [
        pkgs.bat
        pkgs.chafa
        pkgs.coreutils
        pkgs.file
        pkgs."poppler-utils"
      ];
      text = ''
        if [ "$#" -ne 1 ]; then
          echo "usage: pview FILE" >&2
          exit 2
        fi

        target="$1"
        mime="$(file --brief --mime-type "$target")"

        case "$mime" in
          image/*)
            exec chafa "$target"
            ;;
          application/pdf)
            tmp="$(mktemp -d)"
            trap 'rm -rf "$tmp"' EXIT
            pdftoppm -f 1 -l 1 -singlefile -png "$target" "$tmp/page" >/dev/null
            chafa "$tmp/page.png"
            ;;
          text/*|application/json|application/xml|application/x-shellscript)
            exec bat --paging=always --style=plain "$target"
            ;;
          *)
            file "$target"
            echo "Use pget '$target' to download it through the current tssh session." >&2
            ;;
        esac
      '';
    };
  in
    pkgs.symlinkJoin {
      name = "wsl-remote-ux-tools";
      paths = [
        nvimOsc52
        oscCopy
        pget
        pput
        pserve
        pview
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

    users.users.${cfg.user}.openssh.authorizedKeys.keys = cfg.authorizedKeys;

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
          chafa
          micromamba
          p7zip
          miniserve
          mupdf-headless
          neovim
          podman
          qpdf
          pkgs."poppler-utils"
          ripgrep-all
          remoteUxTools
          rsync
          trzsz-go
          uv
          viu
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
