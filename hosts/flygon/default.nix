{pkgs, ...}: let
  user = "me";
  loginKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFs1Ljh6faseFzEG9B0jufOsmc8wMIDxMwiROfp9u3zC me@mini-me.local";
in {
  imports = [
    ./disk-config.nix
    ./hardware-configuration.nix
    ../../modules/github-cli.nix
    ../../modules/hunk.nix
    ../../modules/neovim.nix
    ../../modules/shared
  ];

  networking = {
    hostName = "flygon";
    networkmanager.enable = true;
    useDHCP = false;
    firewall = {
      enable = true;
      allowedTCPPorts = [22];
    };
  };

  time.timeZone = "America/Los_Angeles";

  boot.loader = {
    efi.canTouchEfiVariables = true;
    efi.efiSysMountPoint = "/efi";
    systemd-boot.enable = true;
    systemd-boot.configurationLimit = 10;
  };

  nix = {
    settings = {
      experimental-features = ["nix-command" "flakes"];
      trusted-users = ["root" user];
      substituters = ["https://cache.nixos.org" "https://nix-community.cachix.org"];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };
  };

  programs = {
    dconf.enable = true;
    nix-ld.enable = true;
    niri.enable = true;
    zsh.enable = true;
  };

  services = {
    blueman.enable = true;
    fprintd.enable = true;
    fwupd.enable = true;
    greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --remember --cmd ${pkgs.niri}/bin/niri-session";
        user = "greeter";
      };
    };
    gvfs.enable = true;
    keyd = {
      enable = true;
      keyboards.default = {
        ids = ["*"];
        settings.main.capslock = "overload(control, esc)";
      };
    };
    openssh = {
      enable = true;
      settings = {
        AllowUsers = [user];
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      wireplumber.enable = true;
    };
    power-profiles-daemon.enable = true;
    tumbler.enable = true;
    udisks2.enable = true;
  };

  security.polkit.enable = true;
  security.rtkit.enable = true;

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  systemd.user.services = {
    flygon-kanshi = {
      description = "Apply Flygon display profiles";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig = {
        ExecStart = "${pkgs.kanshi}/bin/kanshi";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
    flygon-mako = {
      description = "Wayland notification daemon";
      wantedBy = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      after = ["graphical-session.target"];
      serviceConfig.ExecStart = "${pkgs.mako}/bin/mako";
    };
  };

  local.githubCli = {
    enable = true;
    inherit user;
  };
  local.git = {
    enable = true;
    inherit user;
  };
  local.hunk = {
    enable = true;
    inherit user;
  };
  local.neovim = {
    enable = true;
    inherit user;
  };
  local.zsh = {
    enable = true;
    inherit user;
    projectDirectories = ["~/projects"];
  };

  hjem.users.${user} = {
    xdg.config.files."kanshi/config" = {
      text = ''
        profile undocked {
          output eDP-1 enable scale 1.33
        }

        profile docked {
          output eDP-1 disable
          output "Acer Technologies XV272U 0x0261D001" position 1620,0
          output "Dell Inc. DELL G2724D 5LFZ5Y3" position 4180,0
        }
      '';
      clobber = true;
    };
  };

  users.groups.${user}.gid = 1000;

  users.users.${user} = {
    uid = 1000;
    group = user;
    isNormalUser = true;
    extraGroups = ["networkmanager" "wheel"];
    openssh.authorizedKeys.keys = [loginKey];
  };
  users.mutableUsers = true;

  environment.systemPackages = import ./packages.nix {inherit pkgs;};
  fonts.packages = with pkgs; [nerd-fonts.iosevka-term];

  system.stateVersion = "26.05";
}
