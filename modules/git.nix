{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.local.git;
  gitConfigFormat = pkgs.formats.gitIni {};
  homeDirectory =
    if pkgs.stdenv.isDarwin
    then "/Users/${cfg.user}"
    else "/home/${cfg.user}";

  defaultSettings = {
    init.defaultBranch = "main";
    core = {
      editor = "vim";
      autocrlf = "input";
    };
    user = {
      name = "midsorbet";
      email = "6295956+midsorbet@users.noreply.github.com";
    };
  };

  signingSettings = lib.optionalAttrs cfg.commitSigning.enable {
    user.signingkey = cfg.commitSigning.keyPath;
    gpg.format = "ssh";
    commit.gpgsign = true;
  };

  settings = lib.recursiveUpdate (lib.recursiveUpdate defaultSettings cfg.settings) signingSettings;
in {
  options.local.git = {
    enable = lib.mkEnableOption "Hjem-managed Git defaults";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User that should own the Hjem-managed Git config.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.git;
      description = "Git package to install.";
    };

    settings = lib.mkOption {
      type = gitConfigFormat.type;
      default = {};
      description = "Additional Git configuration merged into the managed ~/.gitconfig.";
    };

    commitSigning = {
      enable = lib.mkEnableOption "SSH commit signing";

      keyPath = lib.mkOption {
        type = lib.types.str;
        default = "${homeDirectory}/.ssh/id_github.pub";
        description = "Public SSH key path used as Git user.signingkey.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    hjem.users.${cfg.user}.files.".gitconfig" = {
      source = gitConfigFormat.generate "gitconfig" settings;
      clobber = true;
    };
  };
}
