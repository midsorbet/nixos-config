{
  config,
  lib,
  nix-wrapper-modules,
  pkgs,
  ...
}: let
  cfg = config.local.git;
  gitConfigFormat = pkgs.formats.gitIni {};
  homeDirectory =
    if pkgs.stdenv.isDarwin
    then "/Users/${cfg.user}"
    else "/home/${cfg.user}";

  globalIgnore = pkgs.writeText "git-global-ignore" ''
    **/.claude/settings.local.json
  '';

  defaultSettings = {
    init.defaultBranch = "main";
    core = {
      editor = "vim";
      autocrlf = "input";
      excludesFile = globalIgnore;
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

  gitWrapperModule = {
    pkgs,
    wlib,
    ...
  }: {
    imports = [wlib.modules.default];

    config = {
      package = pkgs.git;
      env.GIT_CONFIG_SYSTEM = gitConfigFormat.generate "git-system-config" settings;
    };
  };

  wrappedGit = nix-wrapper-modules.lib.evalPackage [
    gitWrapperModule
    {inherit pkgs;}
  ];
in {
  options.local.git = {
    enable = lib.mkEnableOption "Git configuration built with nix-wrapper-modules";

    user = lib.mkOption {
      type = lib.types.str;
      default = "me";
      description = "User whose home paths are referenced by the wrapped Git configuration.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = wrappedGit;
      description = "Wrapped Git package to install.";
    };

    settings = lib.mkOption {
      type = gitConfigFormat.type;
      default = {};
      description = "Additional system-level defaults merged into the wrapped Git configuration.";
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
  };
}
