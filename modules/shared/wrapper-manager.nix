{
  config,
  lib,
  pkgs,
  wrapper-manager,
  ...
}: let
  cfg = config.local.wrapperManager;
  wrapperManager = wrapper-manager.lib {
    inherit pkgs;
    specialArgs = {
      gitCommitSigning = cfg.git.commitSigning;
      gitPager = cfg.git.pager;
    };
    modules = let
      entries = builtins.readDir ../wrapper-manager;
    in
      map (name: ../wrapper-manager/${name}) (builtins.attrNames entries);
  };
  wrapperPackages = wrapperManager.config.build.packages;
in {
  options.local.wrapperManager.git.commitSigning = {
    enable = lib.mkEnableOption "SSH commit signing for the wrapped git package";
    keyPath = lib.mkOption {
      type = lib.types.str;
      default = "~/.ssh/id_github.pub";
      description = "Public SSH key path passed to Git as user.signingkey when commit signing is enabled.";
    };
  };

  options.local.wrapperManager.git.pager = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "Value for Git core.pager in the wrapped Git package.";
  };

  config.environment.systemPackages =
    builtins.attrValues (removeAttrs wrapperPackages ["zsh"])
    ++ lib.optional (wrapperPackages ? zsh) (lib.hiPrio wrapperPackages.zsh);
}
