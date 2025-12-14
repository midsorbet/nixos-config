{ agenix, config, pkgs, ... }:

let user = "me"; in

{

  imports = [
    ../../modules/darwin/secrets.nix
    ../../modules/darwin/home-manager.nix
    ../../modules/shared
     agenix.darwinModules.default
  ];

  # Setup user, packages, programs
  nix = {
    package = pkgs.nix;

    settings = {
      trusted-users = [ "@admin" "${user}" ];
      substituters = [ "https://nix-community.cachix.org" "https://cache.nixos.org" ];
      trusted-public-keys = [ "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" ];
    };

    gc = {
      automatic = true;
      interval = { Weekday = 0; Hour = 2; Minute = 0; };
      options = "--delete-older-than 30d";
    };

    extraOptions = ''
      experimental-features = nix-command flakes
      extra-platforms = x86_64-darwin aarch64-darwin
    '';

    linux-builder.enable = true;
  };

  # Turn off NIX_PATH warnings now that we're using flakes

  # Load configuration that is shared across systems
  environment.systemPackages = with pkgs; [
    agenix.packages."${pkgs.stdenv.hostPlatform.system}".default
  ] ++ (import ../../modules/shared/packages.nix { inherit pkgs; });

  services.aerospace = {
    enable = true;
    settings = {
      on-focus-changed = [ "move-mouse window-lazy-center" ];
      mode.main.binding = {
        alt-h = "focus left";
        alt-j = "focus down";
        alt-k = "focus up";
        alt-l = "focus right";

        alt-shift-h = "move left";
        alt-shift-j = "move down";
        alt-shift-k = "move up";
        alt-shift-l = "move right";

        alt-minus = "resize smart -50";
        alt-equal  = "resize smart +50";

	alt-1 = "workspace 1";
	alt-2 = "workspace 2";
	alt-3 = "workspace 3";
	alt-4 = "workspace 4";
	alt-5 = "workspace 5";
	alt-6 = "workspace 6";
	alt-7 = "workspace 7";
	alt-8 = "workspace 8";
	alt-9 = "workspace 9";
	alt-a = "workspace A";
	alt-b = "workspace B";
	alt-c = "workspace C";
	alt-d = "workspace D";
	alt-e = "workspace E";
	alt-f = "workspace F";
	alt-g = "workspace G";
	alt-i = "workspace I";
	alt-m = "workspace M";
	alt-n = "workspace N";
	alt-o = "workspace O";
	alt-p = "workspace P";
	alt-q = "workspace Q";
	alt-r = "workspace R";
	alt-s = "workspace S";
	alt-t = "workspace T";
	alt-u = "workspace U";
	alt-v = "workspace V";
	alt-w = "workspace W";
	alt-x = "workspace X";
	alt-y = "workspace Y";
	alt-z = "workspace Z";

	alt-shift-1 = "move-node-to-workspace 1";
	alt-shift-2 = "move-node-to-workspace 2";
	alt-shift-3 = "move-node-to-workspace 3";
	alt-shift-4 = "move-node-to-workspace 4";
	alt-shift-5 = "move-node-to-workspace 5";
	alt-shift-6 = "move-node-to-workspace 6";
	alt-shift-7 = "move-node-to-workspace 7";
	alt-shift-8 = "move-node-to-workspace 8";
	alt-shift-9 = "move-node-to-workspace 9";
	alt-shift-a = "move-node-to-workspace A";
	alt-shift-b = "move-node-to-workspace B";
	alt-shift-c = "move-node-to-workspace C";
	alt-shift-d = "move-node-to-workspace D";
	alt-shift-e = "move-node-to-workspace E";
	alt-shift-f = "move-node-to-workspace F";
	alt-shift-g = "move-node-to-workspace G";
	alt-shift-i = "move-node-to-workspace I";
	alt-shift-m = "move-node-to-workspace M";
	alt-shift-n = "move-node-to-workspace N";
	alt-shift-o = "move-node-to-workspace O";
	alt-shift-p = "move-node-to-workspace P";
	alt-shift-q = "move-node-to-workspace Q";
	alt-shift-r = "move-node-to-workspace R";
	alt-shift-s = "move-node-to-workspace S";
	alt-shift-t = "move-node-to-workspace T";
	alt-shift-u = "move-node-to-workspace U";
	alt-shift-v = "move-node-to-workspace V";
	alt-shift-w = "move-node-to-workspace W";
	alt-shift-x = "move-node-to-workspace X";
	alt-shift-y = "move-node-to-workspace Y";
	alt-shift-z = "move-node-to-workspace Z";

	alt-tab = "workspace-back-and-forth";
	alt-shift-tab = "move-workspace-to-monitor --wrap-around next";
      };
    };
  };

  # Broken: https://github.com/nix-darwin/nix-darwin/issues/1041
  # services.karabiner-elements.enable = true;

  system = {
    checks.verifyNixPath = false;
    primaryUser = user;
    stateVersion = 5;

    defaults = {
      NSGlobalDomain = {
        AppleShowAllExtensions = true;
        ApplePressAndHoldEnabled = false;

        # 120, 90, 60, 30, 12, 6, 2
        KeyRepeat = 2;

        # 120, 94, 68, 35, 25, 15
        InitialKeyRepeat = 15;

        "com.apple.mouse.tapBehavior" = 1;
        "com.apple.sound.beep.volume" = 0.0;
        "com.apple.sound.beep.feedback" = 0;
      };

      dock = {
        autohide = true;
        show-recents = false;
        tilesize = 48;
      };

      finder = {
        AppleShowAllExtensions = true;
      };

      screencapture.location = "~/Pictures/screenshots";

      trackpad = {
        Clicking = true;
        TrackpadThreeFingerDrag = true;
      };
    };
  };
}
